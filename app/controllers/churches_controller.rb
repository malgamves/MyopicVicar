class ChurchesController < InheritedResources::Base
  rescue_from Mongoid::Errors::DeleteRestriction, :with => :record_cannot_be_deleted
  rescue_from Mongoid::Errors::Validations, :with => :record_validation_errors
 layout "places"
 require 'chapman_code'

  def show
   
    if session[:userid].nil?
      redirect_to '/', notice: "You are not authorised to use these facilities"
    end
          @chapman_code = session[:chapman_code] 
          @places = Place.where( :chapman_code => @chapman_code ).all.order_by( place_name: 1)
          @county = session[:county]
          @first_name = session[:first_name]
         
         
          session[:parameters] = params
          load(params[:id])
          @names = Array.new
          @alternate_church_names = @church.alternatechurchnames.all
         
            @alternate_church_names.each do |acn|
              name = acn.alternate_name
              @names << name
            end

  end

  def new
      @church = Church.new
      @county = session[:county]
      @place = Place.where(:chapman_code => ChapmanCode.values_at(@county)).all
      @places = Array.new
          @place.each do |place|
            @places << place.place_name
          end
      @county = session[:county]
      @first_name = session[:first_name]
      @user = UseridDetail.where(:userid => session[:userid]).first

  end

  def create

  if params[:church][:place_name].nil?
    #Only data_manager has ability at this time to change Place so need to use the cuurent place
  place = Place.find(session[:place_id])
  else
  place = Place.where(:chapman_code => ChapmanCode.values_at(session[:county]),:place_name => params[:church][:place_name]).first
  end
  place.churches.each do |church|
    if church.church_name == params[:church][:church_name]
     flash[:notice] = "A church with that name already exists in this place #{place.place_name}"
    redirect_to new_church_path
         return
     end
   end
  church = Church.new(params[:church])
  church.alternatechurchnames_attributes = [{:alternate_name => params[:church][:alternatechurchname][:alternate_name]}] unless params[:church][:alternatechurchname][:alternate_name] == ''
  place.churches << church
  place.save
  # church.save
   if church.errors.any?
    
     flash[:notice] = 'The addition of the Church was unsuccessful'
      redirect_to new_church_path
     return
   else
     flash[:notice] = 'The addition of the Church was successful'
    redirect_to places_path
   end
end
  
  def edit
   
          load(params[:id])
          @chapman_code = session[:chapman_code]
          @place = MasterPlaceName.where(:chapman_code => ChapmanCode.values_at(@county),:disabled.ne => "true").all
          @places = Array.new
          @place.each do |place|
            @places << place.place_name
          end
          @county = session[:county]
          @first_name = session[:first_name]
          @user = UseridDetail.where(:userid => session[:userid]).first
          #set default place name
          @church.update_attributes(:place_name => @place_name)
  end

  def update
  
    load(params[:id])
    old_church = Church.find(params[:id])
    old_church_name = old_church.church_name
    old_place_name = old_church.place.place_name
    @church.church_name = params[:church][:church_name]
    @church.alternatechurchnames_attributes = [{:alternate_name => params[:church][:alternatechurchname][:alternate_name]}] unless params[:church][:alternatechurchname][:alternate_name] == ''
    @church.alternatechurchnames_attributes = params[:church][:alternatechurchnames_attributes] unless params[:church][:alternatechurchnames_attributes].nil?
    @church.denomination = params[:church][:denomination] unless params[:church][:denomination].nil?
    @church.church_notes = params[:church][:church_notes] unless params[:church][:church_notes].nil?
     
     @church.save
     successful = true
     if  (old_church_name != params[:church][:church_name] || old_place_name != params[:church][:place_name])
    
      if @church.registers.count != 0
        @church.registers.each do |register|
          if register.freereg1_csv_files.count != 0
              register.freereg1_csv_files.each do |file|
                success = Freereg1CsvFile.update_file_attribute( file,params[:church][:church_name],params[:church][:place_name] )
                successful = flase unless success
              end #register
           else
              flash[:notice] = 'The Church has no registers or files please delete this one and create a new one in the appropriate Place'
               redirect_to edit_church_path(@church)
              return 
           end # register count
      end #@church registers
     else
       flash[:notice] = 'The Church has no registers or files please delete this one and create a new one in the appropriate Place'
       redirect_to edit_church_path(@church)
       return 
     end # church count
    end #test of church name

   if @church.errors.any? || !successful then
     flash[:notice] = 'The update of the Church was unsuccessful'
    redirect_to edit_church_path(@church)
     return 
   end 
       flash[:notice] = 'The update the Church was successful' 
        @current_page = session[:page]
       session[:page] = session[:initial_page]    
       redirect_to @current_page
  end # end of update
  
  def load(church_id)
    @first_name = session[:first_name]   
    @church = Church.find(church_id)
    session[:church_id] = @church._id
    @church_name = @church.church_name
    session[:church_name] = @church_name
    @place_id = @church.place
    session[:place_id] = @place_id._id
    @place = Place.find(@place_id)
    @place_name = @place.place_name
    session[:place_name] =  @place_name
    @county = ChapmanCode.has_key(@place.chapman_code)
    session[:county] = @county
     @user = UseridDetail.where(:userid => session[:userid]).first
  end

  def destroy
    load(params[:id])
    @church.destroy
     flash[:notice] = 'The deletion of the Church was successful'
    redirect_to places_path
 end

 def record_cannot_be_deleted
   flash[:notice] = 'The deletion of the Church was unsuccessful because there were dependant documents; please delete them first'
  
   redirect_to :action => 'show'
 end

 def record_validation_errors
  flash[:notice] = 'The update of the children to Church with a church name change failed'
 
    redirect_to :action => 'show'
 end

end
