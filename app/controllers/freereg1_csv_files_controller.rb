class Freereg1CsvFilesController < ApplicationController
  require 'chapman_code'
  require 'freereg_options_constants'
  def index
    if params[:page]
    session[:files_index_page] = params[:page]
    end
    #the common listing entry by syndicatep
    @register = session[:register_id]
    get_user_info_from_userid
    @county =  session[:county] unless session[:county].nil?
    @syndicate =  session[:syndicate] unless session[:syndicate].nil?
    @role = session[:role]
    @sorted_by = session[:sorted_by]
    case 
    when session[:my_own]
       @freereg1_csv_files = Freereg1CsvFile.userid(session[:userid]).order_by(session[:sort]).page(params[:page])
    when !session[:syndicate].nil? && session[:userid_id].nil? && (session[:role] == "county_coordinator" || session[:role] == "system_administrator" || session[:role] == "technical" || session[:role] == "volunteer_coordinator" || session[:role] == "syndicate_coordinator" ) 
       @freereg1_csv_files = Freereg1CsvFile.syndicate(session[:syndicate]).order_by(session[:sort]).page(params[:page])
     when !session[:syndicate].nil? && !session[:userid_id].nil? && (session[:role] == "county_coordinator" || session[:role] == "system_administrator" || session[:role] == "technical" || session[:role] == "volunteer_coordinator" || session[:role] == "syndicate_coordinator" ) 
       @freereg1_csv_files = Freereg1CsvFile.userid( UseridDetail.find(session[:userid_id]).userid).order_by(session[:sort]).page(params[:page])
    when !session[:county].nil? && (session[:role] == 'county_coordinator' || session[:role] == "system_administrator" || session[:role] == "technical")
       @freereg1_csv_files = Freereg1CsvFile.county(session[:chapman_code]).order_by(session[:sort]).page(params[:page]) 
    else
    end
  end
    
  def show
    #show an individual batch
    get_user_info_from_userid
    load(params[:id])
    #TODO check on need for these
    @county =  session[:county]
    set_controls
    display_info
    @freereg1_csv_file.adjust_for_collection_information
    @processed = PhysicalFile.where(:userid => @freereg1_csv_file.userid, :file_name => @freereg1_csv_file.file_name).first
    @role = session[:role]
    
  end

  def relocate
    load(params[:id])
    session[:selectcountry] = nil
    session[:selectcounty] = nil
    @records = @freereg1_csv_file.freereg1_csv_entries.count
    set_controls
    max_records = 4000
    max_records = 15000 if @user.person_role == "data_manager" || @user.person_role == "system_administrator"
    if @records.to_i >= max_records
      flash[:notice] = 'There are too many records for an on-line relocation'
      redirect_to :action => 'show' and return
    end
    session[:records] = @records
    display_info
    get_user_info_from_userid
    unless  @user.person_role == 'system_administrator' || @user.person_role == 'data_manager'
      # only senior managers can move betweeen counties and countries; coordinators could loose files
      place = @freereg1_csv_file.register.church.place
      session[:selectcountry] = place.country
      session[:selectcounty] = place.county
      redirect_to :action => 'update_places' and return
    else
      @county =  session[:county]
      set_locations
      #setting these means that we are a DM
      session[:selectcountry] = nil
      session[:selectcounty] = nil
      @countries = ['Select Country','England', 'Islands', 'Scotland', 'Wales']
      @counties = Array.new
      @placenames = Array.new
      @churches = Array.new
    end
  end

  def update_counties
    get_user_info_from_userid
    set_locations
    @freereg1_csv_file = Freereg1CsvFile.find(session[:freereg1_csv_file_id])
    @countries = [params[:country]] 
    session[:selectcountry] = params[:country]
    @counties = ChapmanCode::CODES[params[:country]].keys.insert(0, "Select County")
    @placenames = Array.new
    @churches = Array.new
    display_info
  end

  def update_places
    get_user_info_from_userid
    set_locations
    @freereg1_csv_file = Freereg1CsvFile.find(session[:freereg1_csv_file_id])
    @countries = [session[:selectcountry]]
    if session[:selectcounty].nil?
      #means we are a DM selecting the county
      session[:selectcounty] = ChapmanCode::CODES[session[:selectcountry]][params[:county]] 
      places = Place.chapman_code(session[:selectcounty]).approved.not_disabled.all.order_by(place_name: 1)
    else
      #we are a CC
      places = Place.county(session[:selectcounty]).approved.not_disabled.all.order_by(place_name: 1)
    end
    @counties = Array.new
    @counties << session[:selectcounty]
   
    @placenames = places.map{|a| [a.place_name, a.id]}.insert(0, "Select Place")
    @churches = []
    display_info
  end

  def update_churches
    get_user_info_from_userid
    set_locations
    @freereg1_csv_file = Freereg1CsvFile.find(session[:freereg1_csv_file_id])
    @countries = [session[:selectcountry]]
    @counties = [session[:selectcounty]]
    place = Place.find(params[:place])
    @placenames = Array.new
    @placenames  << place.place_name
    @churches = place.churches.map{|a| [a.church_name, a.id]}.insert(0, "Select Church")
    display_info
  end

   def update_registers
    get_user_info_from_userid
    set_locations
    @freereg1_csv_file = Freereg1CsvFile.find(session[:freereg1_csv_file_id])
    @countries = [session[:selectcountry]]
    @counties = [session[:selectcounty]]
    church = Church.find(params[:church])
    place = church.place
    @placenames = Array.new
    @placenames  << place.place_name
    @churches = Array.new
    @churches << church.church_name
    display_info
  end


  def edit
    #edit the headers for a batch
    load(params[:id])
    set_controls
    get_user_info_from_userid
    display_info
    @county =  session[:county]
    unless session[:error_line].nil?
      #we are dealing with the edit of errors
      @error_message = Array.new
      @content = Array.new
      session[:error_id] = Array.new
      #this need clean up
      @n = 0
      @freereg1_csv_file.batch_errors.where(:freereg1_csv_file_id => params[:id], :error_type => 'Header_Error' ).all.each do |error|
        @error_message[@n] = error.error_message
        @content[@n] = error.data_line
        session[:error_id][@n] = error
        @n = @n + 1
        session[:header_errors] = @n
      end
    end
    #we are correcting the header
    #session role is used to control return navigation options
    @role = session[:role]
    get_places_for_menu_selection
   
  end


  def update
    #update the headers
    load(params[:id])
    set_controls
    get_user_info_from_userid
    @county =  session[:county]
    @role = session[:role]
   if params[:commit] == 'Submit' 
    #lets see if we are moving the file
    @freereg1_csv_file.date_change(params[:freereg1_csv_file][:transcription_date],params[:freereg1_csv_file][:modification_date])
    @freereg1_csv_file.check_locking_and_set(params[:freereg1_csv_file],session)
    @freereg1_csv_file.update_attributes(:alternate_register_name => (params[:freereg1_csv_file][:church_name].to_s + ' ' + params[:freereg1_csv_file][:register_type].to_s ))
    @freereg1_csv_file.update_attributes(params[:freereg1_csv_file])
    @freereg1_csv_file.update_attributes(:modification_date => Time.now.strftime("%d %b %Y"))
    if @freereg1_csv_file.errors.any?  then
      flash[:notice] = 'The update of the batch was unsuccessful'
      render :action => 'edit'
      return
    end
    unless session[:error_line].nil?
      #lets remove the header errors
      @freereg1_csv_file.error =  @freereg1_csv_file.error - session[:header_errors]
      session[:error_id].each do |id|
        @freereg1_csv_file.batch_errors.delete( id)
      end
      @freereg1_csv_file.save
      #clean out the session variables
      session[:error_id] = nil
      session[:header_errors] = nil
      session[:error_line] = nil
    end
    session[:type] = "edit"
    flash[:notice] = 'The update of the batch was successful'
    @current_page = session[:page]
    session[:page] = session[:initial_page]
    redirect_to :action => 'show'
   end
   if params[:commit] == 'Relocate'
     errors =  Freereg1CsvFile.update_location(@freereg1_csv_file,params[:freereg1_csv_file],session[:my_own])
     if errors[0]
       flash[:notice] = errors[1]
       redirect_to :action => "relocate"
       return
     else
      flash[:notice] = 'The relocation of the batch was successful'
      redirect_to :action => 'show'
      return
     end
   end 
  end
  def my_own
    clean_session
    clean_session_for_county
    clean_session_for_syndicate
    get_user_info_from_userid
    session[:my_own] = true
    @freereg1_csv_file = Freereg1CsvFile.new
    @who =  @first_name
    if session[:userid].nil?
      redirect_to '/', notice: "You are not authorised to use these facilities"
      return
    end
    @options= UseridRole::FILE_MANAGEMENT_OPTIONS
  end

  def display_my_own_files
    if params[:page]
     session[:files_index_page] = params[:page]
    end
    get_user_info_from_userid
    @who = @user.userid
    @sorted_by = '(Sorted alphabetically by file name)'
    session[:sort] = "file_name ASC"
    session[:sorted_by] = @sorted_by
    @freereg1_csv_files = Freereg1CsvFile.userid(@user.userid).order_by("file_name ASC").page(params[:page])
    render :index
  end
  def display_my_error_files
    if params[:page]
     session[:files_index_page] = params[:page]
    end
    get_user_info_from_userid
    @who = @user.userid
    @sorted_by = '(Sorted by number of errors)'
     session[:sorted_by] = @sorted_by
    session[:sort] = "error DESC, file_name ASC"
    @freereg1_csv_files = Freereg1CsvFile.userid(@user.userid).order_by("error DESC, file_name ASC").page(params[:page])
    render :index
  end
  def display_my_own_files_by_descending_uploaded_date
    if params[:page]
     session[:files_index_page] = params[:page]
    end
    get_user_info_from_userid
    @who = @user.userid
    @sorted_by = '(Sorted by descending date of uploading)'
    session[:sorted_by] = @sorted_by
    session[:sort] = "uploaded_date DESC"
    @freereg1_csv_files = Freereg1CsvFile.userid(@user.userid).order_by("uploaded_date DESC").page(params[:page])
    render :index
  end
  def display_my_own_files_by_ascending_uploaded_date
    if params[:page]
    session[:files_index_page] = params[:page]
    end
    get_user_info_from_userid
    @who = @user.userid
    @sorted_by = '(Sorted by ascending date of uploading)'
    session[:sort] = "uploaded_date ASC"
     session[:sorted_by] = @sorted_by
    @freereg1_csv_files = Freereg1CsvFile.userid(@user.userid).order_by("uploaded_date ASC").page(params[:page])
    render :index
  end
  def display_my_own_files_by_selection
    get_user_info_from_userid
    @who = @user.userid
    @freereg1_csv_file = Freereg1CsvFile.new
    @freereg1_csv_files = Freereg1CsvFile.userid(@user.userid).order_by("file_name ASC").all
    @files = Hash.new
    @freereg1_csv_files.each do |file|
     @files[":#{file.file_name}"] = file._id unless file.file_name.nil?
    end
    @options = @files
    @location = 'location.href= "/freereg1_csv_files/" + this.value'
    @prompt = 'Select batch'
    render '_form_for_selection'
  end
  def display_my_own_files_waiting_to_be_processed
    get_user_info_from_userid
    @who = @user.userid
    @batches = PhysicalFile.waiting.order_by("waiting_date DESC")
    p @batches  
  end
  def error
    #display the errors in a batch
    load(params[:id])
    display_info
    set_controls
    get_user_info_from_userid
    @county =  session[:county]
    @role = session[:role]
    get_errors_for_error_display
  end

  def by_userid
    #entry by userid
    if params[:page]
    session[:files_index_page] = params[:page]
    end
    session[:page] = request.original_url
    session[:my_own] = false
    session[:userid_id] = params[:id]
    get_user_info_from_userid
    @county =  session[:county]
    @role = session[:role]
    user = UseridDetail.find(params[:id])
    @who = user.userid
    @role = session[:role]
    @freereg1_csv_files = Freereg1CsvFile.userid(user.userid).order_by("file_name ASC", "userid_lower_case ASC").page(params[:page])  unless user.nil?
    render :index
  end

  def create

  end

  def lock
    #lock/unlock a file
    load(params[:id])
    set_controls
    get_user_info_from_userid
    @county =  session[:county]
    @role = session[:role]
    @freereg1_csv_file.lock(session[:my_own])
    flash[:notice] = 'The update of the batch was successful'
    #determine how to return
    redirect_to :back
  end

  def merge
    load(params[:id])
    errors = @freereg1_csv_file.merge_batches 
    if errors[0]  then
      flash[:notice] = "Merge unsuccessful; #{errors[1]}"
      render :action => 'show'
      return
    end
    success = @freereg1_csv_file.calculate_distribution
    if success
      flash[:notice] = 'The merge of the batches was successful'
    else
      flash[:notice] = 'The recalculation of the number of records and distribution was unsuccessful'
    end
    redirect_to freereg1_csv_file_path(@freereg1_csv_file)
  end

  def remove
    #this just removes a batch of records
    load(params[:id])
    session[:freereg1_csv_file_id] =  @freereg1_csv_file._id
    return_location  = @freereg1_csv_file.register
    if @freereg1_csv_file.locked_by_transcriber == 'true' ||  @freereg1_csv_file.locked_by_coordinator == 'true'
      flash[:notice] = 'The removal of the batch was unsuccessful; the batch is locked'
      redirect_to :back
      return
    end
    batch = PhysicalFile.userid(@freereg1_csv_file.userid).file_name(@freereg1_csv_file.file_name).first
    batch.update_attributes(:file_processed =>false, :file_processed_date => nil) if Freereg1CsvFile.where(:file_name => @freereg1_csv_file.file_name, :userid => @freereg1_csv_file.userid).count >= 1
    @freereg1_csv_file.delete 
    flash[:notice] = 'The removal of the batch entry was successful'   
    if session[:my_own]
      redirect_to my_own_freereg1_csv_file_path
      return
    else 
      redirect_to register_path(return_location)
      return
    end
  end

  def destroy
    # this removes all batches and the file
    load(params[:id])
    session[:freereg1_csv_file_id] =  @freereg1_csv_file._id
    return_location  = @freereg1_csv_file.register
    if @freereg1_csv_file.locked_by_transcriber == 'true' ||  @freereg1_csv_file.locked_by_coordinator == 'true'
      flash[:notice] = 'The deletion of the batch was unsuccessful; the batch is locked'
      redirect_to :back
      return
    end
    #there should only be one physical file entry for the same user but just in case
    PhysicalFile.userid(@freereg1_csv_file.userid).file_name(@freereg1_csv_file.file_name).each do |file|
      file.file_delete
      file.delete
    end
    session[:type] = "edit"
    flash[:notice] = 'The deletion of the batches was successful'
    if session[:my_own]
      redirect_to my_own_freereg1_csv_file_path
      return
    else 
      redirect_to register_path(return_location)
      return
    end
  end

  def load(file_id)
    @freereg1_csv_file = Freereg1CsvFile.find(file_id)
  end

  

  def set_controls
    @freereg1_csv_file_name = @freereg1_csv_file.file_name
    session[:freereg1_csv_file_id] =  @freereg1_csv_file._id
    #@first_name = session[:first_name]
    #@user = UseridDetail.where(:userid => session[:userid]).first
    #session[:freereg1_csv_file_name] = @freereg1_csv_file_name
    #session[:county] = ChapmanCode.has_key(@freereg1_csv_file.county)
    #session[:place_name] = @freereg1_csv_file.place
    #session[:church_name] = @freereg1_csv_file.church_name
    #session[:chapman_code] = @freereg1_csv_file.county
  end

  

  def get_errors_for_error_display
    @errors = @freereg1_csv_file.batch_errors.count
    @owner = @freereg1_csv_file.userid
    unless @errors == 0
      lines = @freereg1_csv_file.batch_errors.all
      @role = session[:role]
      @lines = Array.new
      @system = Array.new
      @header = Array.new
      lines.each do |line|
        #need to check this
        #entry = Freereg1CsvEntry.where(freereg1_csv_file_id:  @freereg1_csv_file._id).first
        @lines << line if line.error_type == 'Data_Error'
        @system << line if line.error_type == 'System_Error'
        @header << line if line.error_type == 'Header_Error'
      end
    end
  end
  def display_info
    @freereg1_csv_file_id =   @freereg1_csv_file._id
    @freereg1_csv_file_name = @freereg1_csv_file.file_name
    @register = @freereg1_csv_file.register
    #@register_name = @register.register_name
    #@register_name = @register.alternate_register_name if @register_name.nil?
    @register_name = RegisterType.display_name(@register.register_type)
    @church = @register.church
    @church_name = @church.church_name
    @place = @church.place
    @county =  @place.county
    @place_name = @place.place_name
    
  end
  def set_locations
    @update_counties_location = 'location.href= "/freereg1_csv_files/update_counties?country=" + this.value'
    @update_places_location = 'location.href= "/freereg1_csv_files/update_places?county=" + this.value' 
    @update_churches_location = 'location.href= "/freereg1_csv_files/update_churches?place=" + this.value'
    @update_registers_location = 'location.href= "/freereg1_csv_files/update_registers?church=" + this.value'  
  end

end
