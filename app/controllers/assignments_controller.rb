class AssignmentsController < ApplicationController
  require 'userid_role'
 
  skip_before_filter :require_login, only: [:show]

  def assign
    get_userids_and_transcribers or return
    display_info

    @assign_transcriber_images = ImageServerImage.get_allocated_image_list(params[:id])
    @assign_reviewer_images = ImageServerImage.get_transcribed_image_list(params[:id])

    @assignment = Assignment.new
  end

  def create
    case assignment_params[:type] 
      when 'transcriber'
        image_status = 'ip'
        assign_list = assignment_params[:transcriber_seq]
      when 'reviewer'
        image_status = 'ir'
        assign_list = assignment_params[:reviewer_seq]
    end

    source_id = assignment_params[:source_id]
    user = UseridDetail.where(:userid=>{'$in'=>assignment_params[:user_id]}).first
    instructions = assignment_params[:instructions]

    Assignment.update_or_create_new_assignment(source_id,user.id,instructions,assign_list,image_status)

    ImageServerImage.refresh_image_server_group_after_assignment(assignment_params[:image_server_group_id])

    flash[:notice] = 'Assignment was successful'
    redirect_to index_image_server_image_path(assignment_params[:image_server_group_id])
  end

  def destroy
    display_info
    get_userids_and_transcribers or return

    image_server_image = ImageServerImage.id(params[:id]).first
    assignment_count = ImageServerImage.where(:assignment_id=>image_server_image.assignment_id).count
    assignment = image_server_image.assignment

    image_server_image.update(:assignment_id=>nil, :status=>'a')

    assignment.destroy if assignment_count == 1

    flash[:notice] = 'Deletion of Assignment was successful'
    redirect_to :back
  end

  def display_info
    @register = Register.find(:id=>session[:register_id])
    @register_type = RegisterType.display_name(@register.register_type)
    @church = Church.find(session[:church_id])
    @church_name = session[:church_name]
    @county =  session[:county]
    @place_name = session[:place_name]
    @place = @church.place #id?
    @county =  @place.county
    @place_name = @place.place_name
    @user = cookies.signed[:userid]
    @source = Source.find(:id=>session[:source_id])
    @group = ImageServerGroup.find(:id=>session[:image_server_group_id])
  end

  def edit
  end

  def get_userids_and_transcribers
    @user = cookies.signed[:userid]
    @first_name = @user.person_forename unless @user.blank?

    case session[:manage_user_origin]
      when 'manage county'
        @userids = UseridDetail.where(:syndicate => @user.syndicate, :active=>true).order_by(userid_lower_case: 1)
      when 'manage syndicate'
        @userids = UseridDetail.where(:syndicate => session[:syndicate], :active=>true).all.order_by(userid_lower_case: 1) # need to add ability for more than one syndicate
      else
        flash[:notice] = 'Your account does not support this action'
        redirect_to :back and return
      end

    @people = Array.new
    @userids.each { |ids| @people << ids.userid }
  end

  def list_assignments_by_userid
    display_info
    user_id = assignment_params[:user_id]
    user_ids = Assignment.where(:userid_detail_id=>{'$in'=>user_id}).pluck(:userid_detail_id)

    if user_ids.empty?
      flash[:notice] = 'No assignment for selected user'
    else
      @assignment = Assignment.collection.aggregate([
                {'$match'=>{"userid_detail_id"=>{'$in'=>user_ids}}},
                {'$lookup'=>{from: "userid_details", localField: "userid_detail_id", foreignField: "_id", as:"userids"}},
                {'$lookup'=>{from: "image_server_images", localField: "_id", foreignField: "assignment_id", as: "images"}}, 
                {'$unwind'=>{'path'=>"$userids"}},
                {'$unwind'=>{'path'=>"$images"}}, 
                {'$sort'=>{'userids.userid'=>1, 'images.status'=>1, 'images.seq'=>1}}
             ])

      group_by_count = Assignment.collection.aggregate([
                {'$match'=>{"userid_detail_id"=>{'$in'=>user_ids}}},
                {'$lookup'=>{from: "userid_details", localField: "userid_detail_id", foreignField: "_id", as:"userids"}},
                {'$lookup'=>{from: "image_server_images", localField: "_id", foreignField: "assignment_id", as: "images"}}, 
                {'$unwind'=>{'path'=>"$userids"}},
                {'$unwind'=>{'path'=>"$images"}}, 
                {'$sort'=>{'userids.userid'=>1, 'images.status'=>1, 'images.seq'=>1}}, 
                {'$group'=>{_id:{user:"$userids.userid", status:"$images.status"}, total:{'$sum'=>1}}}
             ])

      @count = Hash.new { |hash, key| hash[key] = Hash.new(&hash.default_proc) }
      group_by_count.each do |x|
        @count[x[:_id][:user]][x[:_id][:status]] = x[:total]
      end
    end
  end

  def new      
  end

  def re_assign
    get_userids_and_transcribers or return
    display_info

    @assignment = Assignment.where(:source_id=>@source.id).first

    @reassign_transcriber_images = ImageServerImage.get_in_progress_image_list(params[:id])
    @reassign_reviewer_images = ImageServerImage.get_in_review_image_list(params[:id])

    if @assignment.nil?
      flash[:notice] = 'No assignment in this Image Source'
      redirect_to :back
    end
  end

  def select_user
    display_info

    users = UseridDetail.where(:syndicate => session[:syndicate], :active=>true).pluck(:id, :userid)
    @people = Hash.new{|h,k| h[k]=[]}.tap{|h| users.each{|k,v| h[k]=v}}
    @location = 'location.href= "/assignments/assignments_by_userid"'

    image_server_image = ImageServerImage.where(:image_server_group_id=>params[:id], :assignment_id=>{'$nin'=>[nil,'']})

    if image_server_image.empty? || image_server_image.nil?
      @assignment = nil
    else
      @assignment = Assignment.where(:id=>image_server_image.first.assignment_id).first
    end

    if @assignment.nil?
      flash[:notice] = 'No assignment in this Image Source'
      redirect_to :back
    end
  end

  def show
  end

  def update
    case params[:_method]
      when 'put'
        assignment_id = params[:id]
        orig_status = params[:status]

        case params[:type]
          when 'complete'
            new_status = orig_status == 'ip' ? 't' : 'r'
            flash[:notice] = 'Modify inmage status to COMPLETE was successful'
          when 'unallocate'
            new_status = orig_status == 'ip' ? 'a' : 't'
            flash[:notice] = 'Modify image status to UNALLOCATE was successful'
          when 'error'
            new_status = 'e'
            flash[:notice] = 'Modify image status to ERROR was successful'
        end

        Assignment.bulk_update_assignment(assignment_id,orig_status,new_status)
        redirect_to select_user_assignment_path
      else
        source_id = assignment_params[:source_id]
        user = UseridDetail.where(:userid=>{'$in'=>assignment_params[:user_id]}).first
        instructions = assignment_params[:instructions]
        image_status = nil

        case assignment_params[:type] 
          when 'transcriber'
            reassign_list = assignment_params[:transcriber_seq]
          when 'reviewer'
            reassign_list = assignment_params[:reviewer_seq]
          else
        end

        Assignment.update_or_create_new_assignment(source_id,user.id,instructions,reassign_list,image_status)

        flash[:notice] = 'Re_assignment was successful'
        redirect_to index_image_server_image_path(assignment_params[:image_server_group_id])
    end
  end

  private
  def assignment_params
    params.require(:assignment).permit! if params[:_method] != 'put'
  end

end
