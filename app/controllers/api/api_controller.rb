class Api::ApiController < ApplicationController
  include ApiHelper

  skip_filter :fetch_community
  skip_filter :cannot_access_without_joining

  skip_before_filter :verify_authenticity_token

  prepend_before_filter :get_api_key
  before_filter :ensure_api_enabled, :set_correct_mime_type
  before_filter :set_current_community_if_given, :set_current_user_if_authorized_request
  before_filter :set_pagination

  respond_to :json, :atom

  layout false

  # used to check if the client software is using a supported API version
  def version_check
    returned_info = {}
    if api_version.to_s == "2"
      returned_info["your_version"] = "latest"
    elsif api_version.to_s == "1" || api_version.to_s == "alpha"
      returned_info["your_version"] = "deprecated"
    else
      returned_info["your_version"] = "not_supported"
    end
    returned_info["message"] = nil

    puts returned_info.to_json
    respond_with returned_info.to_json
  end

  protected

  # def rabl(object, template_name = "#{controller_name}/#{action_name}", options = {})
  #   render_json Rabl.render(object, template_name, :view_path => Rails.root.join('app/views'), :format => :json, :scope => self)
  # end

  def ensure_api_enabled
    #puts "CALL TO API, WITH VERSION SPECIFIED TO #{api_version}"
    unless APP_CONFIG.api_enabled
      render :status => :forbidden, :json => ["API is not enabled on this server"]
    end
  end

  def set_correct_mime_type
    if request.env['HTTP_ACCEPT'] && request.env['HTTP_ACCEPT'].match(/application\/vnd\.sharetribe\+json/i)
      request.format = :json
    end
  end

  def get_api_key
    if api_token = params[:api_token].blank? && request.headers["Sharetribe-API-Token"]
      params[:api_token] = api_token
    end
  end

  # Ensure that only users with appropriate visibility settings can view the listing
  def ensure_authorized_to_view_listing(allow_nil=false)
    # if there is no param listing_id the request is probably in listings_controller, where it is just id.
    id = params[:listing_id] || params[:id]
    if allow_nil && id.nil?
      return true
    end

    @listing = Listing.find_by_id(id)
    if @listing.nil?
      response.status = 404
      render :json => ["No listing found with given id"] and return
    end

    unless @listing.visible_to?(@current_user, @current_community)
      if @listing.public?
        # This situation occurs when the user tries to access a listing
        # with a different community_id .
        response.status = 400
        render :json => ["This listing is not visible in given community."] and return
      elsif @current_user
        response.status = 403
        render :json => ["The user doesn't have a permission to see this listing"] and return
      else
        response.status = 401
        render :json => ["This listing is not visible to unregistered users."] and return
      end
    end
  end

  def set_current_community_if_given
    # use the domain picked from the request by default,
    # and it will be set again, if @current_community
    @url_root = "#{request.protocol}#{request.host_with_port}"
    if @current_community = Community.find_by_domain(request.host)

      if params[:community_id] && (params[:community_id].to_s != @current_community.id.to_s)
        response.status = 400
        render :json => ["Community subdomain mismatch with community_id given in params. Using one of these is enough."] and return
      end

    end

    if params["community_id"]
      @current_community = Community.find_by_id(params["community_id"])

      if @current_community.nil?
        response.status = 404
        render :json => ["No community found with given id"] and return
      end
    end

    # Set also @root__url that can be used in building links that point to the right community instead of api subdomain
    @url_root = @current_community.full_url if @current_community

    # Store to thread the service_name used by current community, so that it can be included in all translations
    ApplicationHelper.store_community_service_name_to_thread(service_name)

  end

  def require_community
    unless @current_community
      response.status = 400
      render :json => ["Community must be selected. Easiest done by providing a community_id parameter."] and return
    end
  end

  def set_current_user_if_authorized_request
    # Devise gives us the current_person automatically if valid api_token provided
    @current_user = current_person
  end

  def find_target_person
    if params["person_id"]
      @person = Person.find_by_id(params["person_id"])
      if @person.nil?
        response.status = 404
        render :json => ["No user found with person_id"] and return
      end
    end
  end

  def set_pagination
    @page = params["page"] || 1
    @per_page = params["per_page"] || 50
  end

end
