class DeleteEntriesRecordsForRemovedBatches
  def self.process(len)
    file_for_warning_messages = "log/delete_entries_records_for_removed_batches.log"
    FileUtils.mkdir_p(File.dirname(file_for_warning_messages) )  unless File.exists?(file_for_warning_messages)
    @@message_file = File.new(file_for_warning_messages, "w")
    Mongoid.load!("#{Rails.root}/config/mongoid.yml")
    puts "Deleting entries and records for removed batches from the files collection"
    #extract range of userids
    base_directory = Rails.application.config.datafiles 
    
    len =len.to_i
    
    count = 0
    userids= UseridDetail.all.order_by(userid: 1)
    userids.each do |user|
      userid = user.userid
      unless userid.nil?
      count = count + 1
      break if count == len
      process_files = Array.new
      Freereg1CsvFile.where(userid: userid).order_by(file_name: 1).each do |name| 
        process_files << name.file_name
      end
    
      pattern = File.join(base_directory,userid,"*.csv")
      files = Dir.glob(pattern, File::FNM_CASEFOLD).sort
   
      files.each do |file|
       file_parts = file.split("/")
       file_name = file_parts[-1]
     
       process_files.delete_if {|name| name = file_name}
      end
      p "remove files for #{userid}" 
      p process_files
     end
    end
    
  end #end process
end