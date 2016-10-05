# -*- coding: utf-8 -*-
class Freecen1UpdateProcessor
  require 'freecen1_update_processor'
  require 'freecen_constants'
  require 'chapman_code'
  require 'freecen1_update_processor'


  @@log = ""

  def self.log_message(msg)
    puts msg
    @@log += msg + "\n"
  end

  # check the .../fixed/ directory for 18?1/ctyPARMS.DAT metadata files and
  # return an array of hashes with info about each PARMS.DAT file, including an
  # md5 hash digest of the file for checking if file changed since last update
  def self.get_parms_files_info(parms_dir)
    parms_info = []
    Freecen::CENSUS_YEARS_ARRAY.each do |yy|
      yy_pattern = File.join(parms_dir,yy,'*PARMS.[Dd][Aa][Tt]')
      yy_files = Dir.glob(yy_pattern).sort_by{|f| f.upcase} rescue []
      all_files = Dir.glob(File.join(parms_dir,yy,'*')) rescue []
      unknown_files = all_files - yy_files
      unknown_files.sort_by{|f| f.upcase}.each do |unk_file|
        log_message("***WARNING: SKIPPING metadata with bad FILENAME '#{unk_file}' (should be 'ctyPARMS.DAT', where 'cty' is Chapman code, all upper-case)")
      end
      yy_files.each do |yy_file|
        dig = Digest::MD5.file(yy_file).to_s rescue nil
        bn = File.basename(yy_file) rescue nil
        chap = bn[0,3].upcase rescue nil
        #p "  #{yy} file='#{bn}' chap=#{chap} dig=#{dig}"
        if chap.blank? || bn.blank? || dig.blank? || !ChapmanCode::values.include?(chap)
          log_message("***WARNING: SKIPPING parms file for unrecognized CHAPMAN CODE or failed to compute md5 (possibly a permissions issue?) '#{chap}' ('#{yy_file}')")
        else
          parms_info << {'year' => yy, 'chapman' => chap, 'file' => yy_file, 'base' => bn, 'digest' => dig}
        end
      end
    end
    parms_info
  end



  #call self.get_parms_files_info to get list of all ctyPARMS.DAT files, then
  #compare list to database to see which files have been added, deleted,
  #modified, or stayed the same
  def self.get_parms_changes_info(parms_dir)
    deleted_parms = [] # parms no longer found in file list
    multiple_parms = [] # if the parm has been added multiple times to database, all versions need to be removed and re-loaded
    new_parms = [] # for new parms.dat files
    modified_parms = [] # if digests don't match
    unchanged_parms = []
    
    parms_info = self.get_parms_files_info(parms_dir) rescue []
    #p "#{parms_info.length} ctyPARMS.DAT files found"

    #for each yy/cty pair parms file in database, if not found in the
    # parms_info list then add it to deleted (the file is no longer there)
    all_db_files = Freecen1FixedDatFile.all
    all_db_files.each do |db_file|
      found = false
      parms_info.each_with_index do |pinfo,idx|
        if db_file.year==pinfo['year'] && db_file.chapman_code==pinfo['chapman']
          if pinfo['stat']
            #puts "***WARNING: multiple Freecen1FixedDatFiles for #{pinfo['year']}-#{pinfo['chapman']} in database. Will drop all then reload to try to fix."
            multiple_parms << {'year'=>pinfo['year'],'chapman'=>pinfo['chapman']}
          end
          parms_info[idx]['stat']='ok'
          found = true
          #compare digests to see if file has been modified
          if db_file.file_digest.blank? || (db_file.file_digest != pinfo['digest'])
            modified_parms << pinfo
            parms_info[idx]['stat']='modified'
          else
            unchanged_parms << pinfo
          end
        end
      end
      unless found
        deleted_parms << {'year'=>db_file.year,'chapman'=>db_file.chapman_code}
      end
    end

    #each file in parms_info not already marked with a status is a new file
    parms_info.each do |pinfo|
      unless pinfo['stat']
        new_parms << pinfo
      end
    end
    {'deleted_parms'=>deleted_parms,'multiple_parms'=>multiple_parms,'new_parms'=>new_parms,'modified_parms'=>modified_parms,'unchanged_parms'=>unchanged_parms}
  end



  # check the .../pieces/ directory for CTY/*.VLD validated piece files and
  # return an array of hashes with info about each VLD.DAT file, including an
  # md5 hash digest of the file for checking if file changed since last update
  def self.get_vld_files_info(vld_dir)
    vld_info = []
    all_dirs = Dir.glob(File.join(vld_dir,'*')) rescue []
    all_dirs.sort_by{|f| f.upcase}.each do |dd|
      dd_base = File.basename(dd)
      unless ChapmanCode::values.include?(dd_base)
        log_message("***WARNING: SKIPPING VLD directory '#{dd}' because '#{dd_base}' is not a known Chapman code")
      end
    end
    ChapmanCode::values.sort.each do |chap|
      vld_pattern = File.join(vld_dir,chap,'*.[Vv][Ll][Dd]')
      vld_files = Dir.glob(vld_pattern).sort_by{|f| f.upcase} rescue []
      #puts "#{vld_files.length} VLD files found in #{chap} directory" if vld_files.length > 0
      all_files = Dir.glob(File.join(vld_dir,chap,'*')) rescue []
      unknown_files = all_files - vld_files
      unknown_files.sort_by{|f| f.upcase}.each do |unk_file|
        log_message("***WARNING: SKIPPING file not named *.VLD '#{unk_file}'")
      end
      chap_vlds = []
      vld_files.each do |vld_file|
        dig = Digest::MD5.file(vld_file).to_s rescue nil
        bn = File.basename(vld_file) rescue nil
        if bn.blank? || dig.blank?
          log_message("***ERROR: SKIPPING VLD file because failed to compute md5 (possibly a permissions issue?) '#{vld_file}'")
        else
          if chap_vlds.include?(bn.upcase)
            log_message("***ERROR: SKIPPING VLD file '#{vld_file}' because same filename (except for capitalization) was already read in #{chap} directory")
          else
            vld_info << {'chapman' => chap, 'file' => vld_file, 'base' => bn, 'base_up'=>bn.upcase, 'digest' => dig}
            chap_vlds << bn.upcase
          end
        end
      end
    end
    vld_info
  end



  #call self.get_vld_files_info to get list of all *.VLD validated piece files,
  #then compare list to database to see which files have been added, deleted,
  #modified, or stayed the same
  def self.get_vld_changes_info(vld_dir)
    deleted_vlds = []
    multiple_vlds = []
    new_vlds = []
    modified_vlds = []
    unchanged_vlds = []

    vld_info = self.get_vld_files_info(vld_dir) rescue []
    p "#{vld_info.length} .VLD files found"
    #for each chapman/vld file in the database, if not found in the vld_info
    #list then add it to deleted (the file is no longer there or has been
    #moved to a different county directory)
    all_db_files = Freecen1VldFile.all
    all_db_files.each do |db_file|
      found = false
      db_file_id = db_file._id
      #puts ">>> vld from database: db_file.file_name=#{db_file.file_name}"
      vld_info.each_with_index do |vinfo,idx|
        if db_file.file_name.upcase==vinfo['base_up'] && db_file.chapman_code==vinfo['chapman']
          if vinfo['stat']
            log_message("***ERROR: multiple Freecen1VldFiles for #{vinfo['chapman']}-#{vinfo['base_up']} in database. Will drop all then reload to try to fix.")
            multiple_vlds << {'chapman'=>vinfo['chapman'],'year'=>vinfo['base_up'],'vld_file_id'=>vinfo['db_id']} # the previous one
            multiple_vlds << {'chapman'=>vinfo['chapman'],'year'=>vinfo['base_up'],'vld_file_id'=>db_file_id}
          end
          vld_info[idx]['stat']='ok'
          vld_info[idx]['db_id']=db_file_id
          found = true
          #compare digests to see if file has been modified
          if db_file.file_digest.blank? || db_file.file_digest != vinfo['digest']
            vinfo['vld_file_id'] = db_file_id
            modified_vlds << vinfo
            vld_info[idx]['stat']='modified'
          else
            unchanged_vlds << vinfo
          end
        end
      end
      unless found
        deleted_vlds << {'chapman'=>db_file.chapman_code,'file'=>db_file.file_name,'vld_file_id'=>db_file_id}
      end
    end
    multiple_vlds = multiple_vlds.uniq #some may be in there more than once

    #each file in parms_info not already marked with a status is a new file
    vld_info.each do |vinfo|
      unless vinfo['stat']
        new_vlds << vinfo
      end
    end
    {'deleted_vlds'=>deleted_vlds,'multiple_vlds'=>multiple_vlds,'new_vlds'=>new_vlds,'modified_vlds'=>modified_vlds,'unchanged_vlds'=>unchanged_vlds}
  end



  # if the update is already running, exit, otherwise create file
  # MyopicVicar::Application.config.fc_update_processor_status_file
  # so multiple instances don't start due to cron (or manual) starts
  def self.check_and_set_update_running
    if !MyopicVicar::Application.config.fc_update_processor_status_file.present?
      log_message("***ERROR: MyopicVicar::Application.config.fc_update_processor_status_file is not defined!")
    elsif File.exist?(MyopicVicar::Application.config.fc_update_processor_status_file)
      #status file just has unix timestamp of last start time
      update_start_i = File.read(MyopicVicar::Application.config.fc_update_processor_status_file).to_i rescue 0
      update_start_time = Time.at(update_start_i).to_s
      log_message("***ERROR: freecen1_update_processor self.update_all() started at #{Time.now.to_s} but there seems to be an update process already running (started #{update_start_time}) because file '#{MyopicVicar::Application.config.fc_update_processor_status_file}' exists. Returning without processing.")
      return true
    else
      f = File.new(MyopicVicar::Application.config.fc_update_processor_status_file, "wb")
      f.write(Time.now.to_i.to_s)
      f.close
    end
    return false
  end

  def self.need_early_exit?()
    return false if File.exist?(MyopicVicar::Application.config.fc_update_processor_status_file)
    log_message("*** skipping some processing due to need_early_exit? == true (file '#{MyopicVicar::Application.config.fc_update_processor_status_file}' no longer exists)\n")
    return true
  end

  def self.update_all(parms_dir, vld_dir)
    update_err_messages = []
    #p "lib/freecen1_update_processor.rb self.update_all() started"
    return if self.check_and_set_update_running #return early if already running
    start_time = Time.now
    log_message("start time=#{start_time.to_s}\n")

    app_name = MyopicVicar::Application.config.template_set
    unless 'freecen'==app_name
      log_message("***ERROR: freecen1_update_processor started but app='#{app_name}'")
      return
    end
    log_message("\n--------reading ctyPARMS.dat files")
    parms_changes = self.get_parms_changes_info(parms_dir) rescue []

    deleted_parms = parms_changes['deleted_parms']
    multiple_parms = parms_changes['multiple_parms']
    new_parms = parms_changes['new_parms']
    modified_parms = parms_changes['modified_parms']
    unchanged_parms = parms_changes['unchanged_parms']
    log_message("----DELETED PARMS (#{deleted_parms.length})--\n#{deleted_parms.inspect}")
    log_message("----MULTIPLE PARMS (#{multiple_parms.length})--\n#{multiple_parms.inspect}")
    log_message("----NEW PARMS (#{new_parms.length})--\n#{new_parms.inspect}")
    log_message("----MODIFIED PARMS (#{modified_parms.length})--\n#{modified_parms.inspect}")
    log_message("----UNCHANGED PARMS (#{unchanged_parms.length})--\n (not listing unchanged parms)\n")

    log_message("\n--------reading .VLD validated piece files")
    vld_changes = self.get_vld_changes_info(vld_dir)
    #puts "self.get_vld_changes_info() done"
    deleted_vlds = vld_changes['deleted_vlds']
    multiple_vlds = vld_changes['multiple_vlds']
    new_vlds = vld_changes['new_vlds']
    modified_vlds = vld_changes['modified_vlds']
    unchanged_vlds = vld_changes['unchanged_vlds']
    log_message("----DELETED VLDS (#{deleted_vlds.length})--\n#{deleted_vlds.inspect}")
    log_message("----MULTIPLE VLDS (#{multiple_vlds.length})--\n#{multiple_vlds.inspect}")
    log_message("----NEW VLDS (#{new_vlds.length})--\n#{new_vlds.inspect}")
    log_message("----MODIFIED VLDS (#{modified_vlds.length})--\n#{modified_vlds.inspect}")
    log_message("----UNCHANGED VLDS (#{unchanged_vlds.length})--\n (not listing unchanged VLDs)")
    
    log_message("\n---1----Saving edited geolocation info from deleted and modified PARMS pieces:")
    log_message("*** Not implemented within scope of story #61 (version 1.1). Should be done as a story in version 1.2")

    log_message("\n---2----Deleting deleted VLDs from database:")
    deleted_vlds.each do |vld|
      break if self.need_early_exit?
      begin
        self.delete_vld_from_db(vld['vld_file_id'])
      rescue => e #rescue any exceptions and continue processing the other VLDs
        log_message(e.message)
        update_err_messages << e.message
      end
    end

    log_message("\n---3----Deleting duplicate VLDs from database to try to fix:")
    #for each duplicate: delete all that match, (will reload valid ones later)
    multiple_vlds.each do |vld|
      break if self.need_early_exit?
      begin
        self.delete_vld_from_db(vld['vld_file_id'])
      rescue
        log_message(e.message)
        update_err_messages << e.message
      end
    end

    log_message("\n---4----Dropping deleted PARMS (and all associated VLDs):")
    deleted_parms.each do |dp|
      break if self.need_early_exit?
      begin
        self.delete_parms_and_associated_vlds_from_db(dp['year'], dp['chapman'])
      rescue => e #rescue any exceptions and continue processing the other VLDs
        log_message(e.message)
        update_err_messages << e.message
      end
    end

    log_message("\n---5----Dropping duplicate PARMS (and all associated VLDs):")
    multiple_parms.each do |dp|
      break if self.need_early_exit?
      begin
        self.delete_parms_and_associated_vlds_from_db(dp['year'], dp['chapman'])
      rescue => e #rescue any exceptions and continue processing the other VLDs
        log_message(e.message)
        update_err_messages << e.message
      end
    end

    log_message("\n---6----Dropping modified PARMS (and all associated VLDs):")
    modified_parms.each do |dp|
      break if self.need_early_exit?
      begin
        self.delete_parms_and_associated_vlds_from_db(dp['year'], dp['chapman'])
      rescue => e #rescue any exceptions and continue processing the other VLDs
        log_message(e.message)
        update_err_messages << e.message
      end
    end

    

    log_message("\n---7---Loading/Reloading new and modified PARMS files:")
    #check changes again, all that need to be reloaded should also be "new" now
    parms_changes = self.get_parms_changes_info(parms_dir) rescue []
    new_parms = parms_changes['new_parms']
    new_parms.each do |np|
      break if self.need_early_exit?
      begin
        self.process_parms_file(np['file'])
      rescue => e #rescue any exceptions and continue processing the other VLDs
        log_message(e.message)
        update_err_messages << e.message
      end
    end


    log_message("\n---8---Load new VLDs, and reload any dropped due to modifications:")
    vld_changes = self.get_vld_changes_info(vld_dir)
    new_vlds = vld_changes['new_vlds']
    new_vlds.each do |nv|
      break if self.need_early_exit?
      begin
        self.process_vld_file(nv['file'])
      rescue => e #rescue any exceptions and continue processing the other VLDs
        log_message(e.message)
        update_err_messages << e.message
      end
    end

    log_message("\n---9---Update piece subplaces geolocation info for PARMS that were loaded")
    log_message("*** Not implemented within scope of story #61 (version 1.1). Should be done as a story in version 1.2")

    #delete the update processor status file so processor will run next time
    if File.exist?(MyopicVicar::Application.config.fc_update_processor_status_file)
      File.delete(MyopicVicar::Application.config.fc_update_processor_status_file)
    end

    # update places cache is currently done by calling the rake task separately
    # from the script /lib/tasks/scripts/update_freecen2_production.sh
    # In a future version, we may want to only update those portions of the
    # places cache that correspond to changes made in this update

    log_message("\n---DONE---emailing report to admins, manager")
    # send update_err_messages and rest of report to admins, manager
    log_message("end time=#{Time.now.to_s}")
    self.send_update_report()

    log_message("lib/freecen1_update_processor.rb self.process_all() finished")

  end

  #delete a Freecen1VldFile from the database, along with its vld entries,
  #dwellings, individuals, searchrecords, etc.
  def self.delete_vld_from_db(vld_id)
    piece = nil
    vld = Freecen1VldFile.where("_id" => vld_id).first
    unless vld.nil?
      log_message("  delete from db: (#{vld.full_year}-#{vld.dir_name} #{File.basename(vld.file_name)}")
      #freecen1_vld_file freecen1_vld_entry freecen_dwelling freecen_individual
      #search_record(each individual)
      #freecen_piece place? freecen1_fixed_dat_entry
      vld_dwellings = FreecenDwelling.where(:freecen1_vld_file_id => vld_id).entries
      tot_indiv = 0
      tot_search_rec = 0
      tot_dwel = 0
      #delete all search records, dwellings, and individuals for vld
      vld_dwellings.each do |dwel|
        piece = dwel.freecen_piece if piece.nil?
        if piece._id != dwel.freecen_piece_id
          log_message("***ERROR: failed sanity check in delete_vld_from_db() unexpected piece id")
        end
        individuals = FreecenIndividual.where(:freecen_dwelling_id => dwel._id)
        individuals.each do |indiv|
          tot_indiv += 1
          sr = indiv.search_record
          sr.delete unless sr.nil? #delete search record
          tot_search_rec += 1 unless sr.nil?
          indiv.delete #delete individual
        end unless individuals.nil?
        dwel.delete #delete dwelling
        tot_dwel += 1
      end unless vld_dwellings.nil?

      # remove all other Freecen1VldEntries (for uninhabited buildings,
      # building in progress, etc.) that did not have any individuals
      vld_entries = Freecen1VldEntry.where(:freecen1_vld_file_id => vld_id).entries
      tot_other = 0
      vld_entries.each do |ve|
        ve.delete # delete entry that wasn't an individual
        tot_other += 1
      end unless vld_entries.nil?
      log_message(" deleted individuals:#{tot_indiv}  other entries:#{tot_other}  dwellings:#{tot_dwel}")

      # update the count of individuals in the piece
      piece.inc(:num_individuals => -1*tot_indiv) unless piece.nil?
    end

    #sanity check-----------------------------
    #are there dwellings left that belong to the vld file?
    orphaned_dwellings = FreecenDwelling.where(:freecen1_vld_file_id => vld_id).entries
    if orphaned_dwellings && orphaned_dwellings.length > 0
      log_message("***ERROR: Sanity check failed. #{orphaned_dwellings.length} dwellings left after delete_vld_from_db() should have deleted them all")
    end
    vld.delete unless vld.nil?
  end

  def self.process_vld_file(vld_pathname)
    log_message(" starting self.process_vld_file() for #{vld_pathname}")

    #use same logic as in process_freecen1_vld.rake process_file
    parser = Freecen::Freecen1VldParser.new
    file_record = parser.process_vld_file(vld_pathname)
    transformer = Freecen::Freecen1VldTransformer.new
    transformer.transform_file_record(file_record)
    
    translator = Freecen::Freecen1VldTranslator.new
    translator.translate_file_record(file_record)
    log_message("\t#{vld_pathname} contained #{file_record.freecen_dwellings.count} dwellings in #{file_record.freecen1_vld_entries.count} entries\n")
  end



  def self.delete_parms_and_associated_vlds_from_db(year, chapman)
    parms_matches = Freecen1FixedDatFile.where(:year => year, :chapman_code => chapman).entries
    parms_matches.each do |pmatch|
      log_message(" dropping #{pmatch['chapman_code']}-#{pmatch['year']} ")
      parm_vlds = Freecen1VldFile.where(:dir_name => chapman, :full_year => year).entries
      log_message("  (and #{parm_vlds.length} associated VLDs)") unless parm_vlds.blank?
      parm_vlds.each do |parm_vld|
        self.delete_vld_from_db(parm_vld._id)
      end unless parm_vlds.blank?
      self.delete_parms_from_db(pmatch._id)
    end unless parms_matches.blank?
  end



  def self.delete_parms_from_db(parms_id)
    parms = Freecen1FixedDatFile.where(:_id => parms_id).first
    if(parms.nil?)
      log_message("***ERROR: self.delete_parms_from_db couldn't find parms with id #{parms_id}")
      return;
    end
    log_message(" starting self.delete_parms_from_db() for #{parms.year}/#{parms.chapman_code} #{parms.filename}")

    #for each freecen1_fixed_dat_entries that have freecen1_fixed_dat_file_id
    # same as this parms._id:
    fixed_entries = Freecen1FixedDatEntry.where(:freecen1_fixed_dat_file_id => parms._id).entries
    fixed_entries.each do |fe|
      # find the FreecenPiece for the fixed_dat_entry
      pieces = FreecenPiece.where(:freecen1_fixed_dat_entry_id => fe._id).entries
#      puts "  found #{pieces.length} pieces for entry" unless pieces.nil?
      pieces.each do |pc|
        if pc.num_individuals != 0
          log_message("***ERROR: num_individuals for piece==#{pc.num_individuals} (expected 0)")
        end
        pc.delete #delete the freecen_piece from database
      end
      fe.delete #delete the Freecen1FixedDatEntry from database
    end
    
    #  sanity check: verify that no vld files for this year/county still exist
    vlds = Freecen1VldFile.where(:full_year => parms.year, :dir_name => parms.chapman_code).entries
    if vlds.present?
      log_message("***ERROR: expected all Freecen1VldFiles to be gone from database for  year=#{parms.year}, chapman=#{parms.chapman_code} after deleting parms file")
    end

    parms.delete #delete the freecen1_fixed_dat_file from database
  end


  def self.process_parms_file(parms_pathname)
    log_message("starting self.process_parms_file() for #{parms_pathname}")

    #use same logic as in process_freecen1_vld.rake process_file
    parser = Freecen::Freecen1MetadataDatParser.new
    file_record = parser.process_dat_file(parms_pathname)
    
    transformer = Freecen::Freecen1MetadataDatTransformer.new
    transformer.transform_file_record(file_record)
    
    translator = Freecen::Freecen1MetadataDatTranslator.new
    translator.translate_file_record(file_record)
    log_message("\t#{parms_pathname} contained #{file_record.freecen1_fixed_dat_entries.count} entries")
  end

  def self.send_update_report()
    user = UseridDetail.where(userid: "CENManager").first
    admins = UseridDetail.where(person_role: "system_administrator").entries
    if user.nil? && admins.blank?
      log_message("***ERROR: No system_administrators or CENManager found to email report")
      return
    end
    user = admins[0] if user.nil?
    ccs = []
    admins.each do |u|
      ccs << u.email_address
    end
    ccs = ccs.uniq
    ccs = nil if ccs.length < 1
    report = @@log
    puts " calling UserMailer.update_report_to_freecen_manager(report,user,ccs)"
    UserMailer.update_report_to_freecen_manager(report,user,ccs).deliver_now
    puts " done calling UserMailer.update_report_to_freecen_manager()"
  end

end