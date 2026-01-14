# frozen_string_literal: true

class ProfileSectionsController < ApplicationController
  before_action :authorize

  def create
    attributes = permitted_params
    if attributes[:text].present? && attributes[:type] == "SellerProfileRichTextSection"
      processed_content = process_text(attributes[:text][:content])
      attributes[:text][:content] = processed_content
    end

    section = current_seller.seller_profile_sections.create(attributes)
    return render json: { error: section.errors.full_messages.to_sentence }, status: :unprocessable_entity if section.errors.present?
    render json: { id: section.external_id }
  rescue ActiveRecord::SubclassNotFound
    render json: { error: "Invalid section type" }, status: :unprocessable_entity
  end

  def update
    section = current_seller.seller_profile_sections.find_by_external_id!(params[:id])
    attributes = permitted_params
    attributes.delete(:shown_posts)
    if attributes[:text].present? && section.is_a?(SellerProfileRichTextSection)

      ## block iframe intercept
      return head :ok unless validate_iframe_src!(attributes[:text][:content])
      
      processed_content = process_text(attributes[:text][:content], section.json_data["text"]["content"] || [])
      attributes[:text][:content] = processed_content
    end

    unless section.update(attributes)
      render json: { error: section.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

 ## block intercept code
 def validate_iframe_src!(content)
  content.each do |node|
    next unless node[:type] == "raw"

    iframe = Nokogiri::HTML.fragment(node.dig(:attrs, :html)).at("iframe")
    return false unless iframe

    src = iframe["src"].to_s.strip
    return false unless src.start_with?(
      "https://cdn.iframe.ly/api/iframe?url="
    )
  end
  true
end
  
  def destroy
    current_seller.seller_profile_sections.find_by_external_id!(params[:id]).destroy!
  end

  private
    def process_text(content, old_content = [])
      SaveContentUpsellsService.new(
        seller: current_seller,
        content:,
        old_content:,
      ).from_rich_content
    end

    def authorize
      super(section_policy)
    end

    def section_policy
      [:profile_section]
    end

    def permitted_params
      permitted_params = params.permit(policy(section_policy).public_send("permitted_attributes_for_#{action_name}"))
      permitted_params[:shown_products]&.map! { ObfuscateIds.decrypt(_1) }
      permitted_params[:shown_posts]&.map! { ObfuscateIds.decrypt(_1) }
      permitted_params[:shown_wishlists]&.map! { ObfuscateIds.decrypt(_1) }
      permitted_params[:product_id] = ObfuscateIds.decrypt(permitted_params[:product_id]) if permitted_params[:product_id].present?
      permitted_params[:featured_product_id] = ObfuscateIds.decrypt(permitted_params[:featured_product_id]) if permitted_params[:featured_product_id].present?
      permitted_params
    end
end
