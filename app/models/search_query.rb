class SearchQuery
  include Mongoid::Document
  store_in session: "local_writable"
  include Mongoid::Timestamps::Created::Short
  include Mongoid::Timestamps::Updated::Short

  require 'chapman_code'
  require 'freereg_options_constants'
  require 'name_role'
  require 'date_parser'
  # consider extracting this from entities
  module SearchOrder
    TYPE='record_type'
    DATE='search_date'
    COUNTY='chapman_code'
    LOCATION='location'
    NAME="transcript_names"

    ALL_ORDERS = [
      TYPE,
      DATE,
      COUNTY,
      LOCATION,
      NAME
    ]
  end

  field :first_name, type: String#, :required => false
  field :last_name, type: String#, :required => false
  field :fuzzy, type: Boolean
  field :role, type: String#, :required => false
  validates_inclusion_of :role, :in => NameRole::ALL_ROLES+[nil]
  field :record_type, type: String#, :required => false
  validates_inclusion_of :record_type, :in => RecordType.all_types+[nil]
  field :chapman_codes, type: Array, default: []#, :required => false
  #  validates_inclusion_of :chapman_codes, :in => ChapmanCode::values+[nil]
  #field :extern_ref, type: String
  field :inclusive, type: Boolean
  field :witness, type: Boolean
  field :start_year, type: Integer
  field :end_year, type: Integer
  has_and_belongs_to_many :places, inverse_of: nil

  field :radius_factor, type: Integer, default: 41
  field :search_nearby_places, type: Boolean

  field :result_count, type: Integer
  field :place_system, type: String, default: Place::MeasurementSystem::ENGLISH

  field :session_id, type: String
  field :runtime, type: Integer
  field :order_field, type: String, default: SearchOrder::DATE
  validates_inclusion_of :order_field, :in => SearchOrder::ALL_ORDERS
  field :order_asc, type: Boolean, default: true
  field :region, type: String #bot honeypot
  field :search_index, type: String
  belongs_to :userid_detail

  embeds_one :search_result

  validate :name_not_blank
  validate :date_range_is_valid
  validate :radius_is_valid
  validate :county_is_valid
  validate :wildcard_is_appropriate
  
  before_validation :clean_blanks

  index({ c_at: 1})

  class << self
     def search_id(name)
      where(:id => name)
     end
  end

  def search
    search_index = SearchRecord.index_hint(search_params)
    records = SearchRecord.collection.find(search_params).hint(search_index).limit(FreeregOptionsConstants::MAXIMUM_NUMBER_OF_RESULTS)
    if can_query_ucf?
      ucf_index = SearchRecord.index_hint(ucf_params)
      ucf_records = SearchRecord.where(ucf_params).hint(ucf_index).limit(FreeregOptionsConstants::MAXIMUM_NUMBER_OF_RESULTS)
      ucf_records = filter_ucf_records(ucf_records)
      # actually filter on them
    end
    self.persist_results(records,search_index)
    records
  end


  def fetch_records
    return @search_results if @search_results
    if self.search_result.present?
      records = self.search_result.records
      begin
        @search_results = SearchRecord.find(records)
      rescue Mongoid::Errors::DocumentNotFound
        logger.warn("FREEREG:SEARCH_ERROR:search record in search results went missing")
        @search_results = nil
      end
    else
      @search_results = nil
    end
    @search_results    
  end

  def persist_results(results,index)
    # finally extract the records IDs and persist them
    records = Array.new
    results.each do |rec|
      records << rec["_id"].to_s
    end
    self.search_result =  SearchResult.new(records: records)
    self.result_count = records.length
    self.runtime = (Time.now.utc - self.updated_at) * 1000
    self.search_index = index
    self.save  
  end

  def compare_name(x,y)
    x_name = x.comparable_name
    y_name = y.comparable_name
    unless x_name.blank? || y_name.blank?
      if x_name['last_name'] == y_name['last_name']
        x_name['first_name'] <=> y_name['first_name']
      else
        x_name['last_name'] <=> y_name['last_name']
      end
    end
  end

  def compare_location(x,y)
    if x.location_names[0] == y.location_names[0]
      if x.location_names[1] == y.location_names[1]
        x.location_names[2] <=> y.location_names[2]
      else
        x.location_names[1] <=> y.location_names[1]
      end
    else
      x.location_names[0] <=> y.location_names[0]
    end
  end

  def sort_results(results)
    # next reorder in memory
    if results.present?
      case self.order_field
      when SearchOrder::COUNTY
        if self.order_asc
          results.sort! { |x, y| x['chapman_code'] <=> y['chapman_code'] }
        else
          results.sort! { |x, y| y['chapman_code'] <=> x['chapman_code'] }
        end
      when SearchOrder::DATE 
        if self.order_asc
          results.sort! { |x,y| (x.search_dates.first||'') <=> (y.search_dates.first||'') }
        else
          results.sort! { |x,y| (y.search_dates.first||'') <=> (x.search_dates.first||'') }        
        end
      when SearchOrder::TYPE
        if self.order_asc
          results.sort! { |x, y| x['record_type'] <=> y['record_type'] }
        else
          results.sort! { |x, y| y['record_type'] <=> x['record_type'] }
        end
      when SearchOrder::LOCATION
        if self.order_asc
          results.sort! do |x, y|
            compare_location(x,y)
          end
        else
          results.sort! do |x, y|
            compare_location(y,x)  # note the reverse order
          end
        end
      when SearchOrder::NAME
        if self.order_asc
          results.sort! do |x, y|
            compare_name(x,y)
          end
        else
          results.sort! do |x, y|
            compare_name(y,x)  # note the reverse order
          end
        end
      end 
    end   
  end

  def results
    records = fetch_records
    sort_results(records) unless records.nil?
    #persist_results(records) unless records.nil? 
    records
  end

  # # all this now does is copy the result IDs and persist the new order
  # def new_order(old_query)
    # # first fetch the actual records
    # records = old_query.search_result.records
    # self.search_result =  SearchResult.new(records: records)
    # self.result_count = records.length
    # self.save    
  # end

  def explain_plan
    SearchRecord.where(search_params).max_scan(1+FreeregOptionsConstants::MAXIMUM_NUMBER_OF_SCANS).asc(:search_date).all.explain
  end

  def explain_plan_no_sort
    SearchRecord.where(search_params).all.explain
  end

  def ucf_params
    params = Hash.new
    params[:record_type] = record_type if record_type
    params.merge!(place_search_params)
    params.merge!(date_search_params)
    params["_id"] = { "$in" => ucf_record_ids } #moped doesn't translate :id into "_id"

    params    
  end

  def can_query_ucf?
    self.places.size > 0
  end

  def ucf_record_ids
    ids = []
    
    self.places.inject([]) { |accum, place| accum + place.ucf_record_ids }
  end

  def filter_ucf_records(records)
    filtered_records = []
    records.each do |record|
      p record.id
      record.search_names.each do |name|
        p name
        if name.type == SearchRecord::PersonType::PRIMARY || self.inclusive
          if name.contains_wildcard_ucf?
            if self.first_name.blank?
              # test surname
              if self.last_name.match(UcfTransformer.ucf_to_regex(name.last_name.downcase))
                filtered_records << record
              end
            elsif self.last_name.blank?
              # test forename
              if self.first_name.match(UcfTransformer.ucf_to_regex(name.first_name.downcase))
                filtered_records << record
              end
            else
              # test both
              print "#{self.last_name.downcase}.match(#{UcfTransformer.ucf_to_regex(name.last_name.downcase).inspect}) && #{self.first_name.downcase}.match(#{UcfTransformer.ucf_to_regex(name.first_name.downcase).inspect}) => #{self.last_name.downcase.match(UcfTransformer.ucf_to_regex(name.last_name.downcase)) && self.first_name.downcase.match(UcfTransformer.ucf_to_regex(name.first_name.downcase))}\n"
              if self.last_name.downcase.match(UcfTransformer.ucf_to_regex(name.last_name.downcase)) && self.first_name.downcase.match(UcfTransformer.ucf_to_regex(name.first_name.downcase)) 
                filtered_records << record
              end
            end        
          end
        end        
      end
    end
    filtered_records
  end

  def search_params
    params = Hash.new
    params[:record_type] = record_type if record_type
    params.merge!(place_search_params)
    params.merge!(date_search_params)
    params.merge!(name_search_params)

    params
  end

  def place_search_params
    params = Hash.new
    if place_search?
      search_place_ids = radius_place_ids
      params[:place_id] = { "$in" => search_place_ids }
    else
      params[:chapman_code] = { '$in' => chapman_codes } if chapman_codes && chapman_codes.size > 0
    end

    params
  end

  def place_search?
    place_ids && place_ids.size > 0
  end

  def radius_place_ids
    radius_ids = []
    all_radius_places.map { |place| radius_ids << place.id }
    radius_ids.concat(place_ids)
    radius_ids.uniq
  end


  def date_search_params
    params = Hash.new
    if start_year || end_year
      date_params = Hash.new
      date_params["$gt"] = DateParser::start_search_date(start_year) if start_year
      date_params["$lt"] = DateParser::end_search_date(end_year) if end_year
      params[:search_dates] = { "$elemMatch" => date_params }
    end
    params
  end
  def previous_record(current)
    records_sorted = self.results
    return nil if records_sorted.nil?
    record_ids_sorted = Array.new
    records_sorted.each do |rec|
      record_ids_sorted << rec["_id"].to_s
    end
    idx = record_ids_sorted.index(current.to_s) unless record_ids_sorted.nil?
    return nil if idx.nil? || idx <= 0
    record = record_ids_sorted[idx-1]
    record
  end
  def next_record(current)
    records_sorted = self.results
    return nil if records_sorted.nil?
    record_ids_sorted = Array.new
    records_sorted.each do |rec|
      record_ids_sorted << rec["_id"].to_s
    end
    idx = record_ids_sorted.index(current.to_s) unless record_ids_sorted.nil?
    return nil if idx.nil?
    record = record_ids_sorted[idx+1]
    record
  end

  def name_search_params
    params = Hash.new
    name_params = Hash.new
    
    type_array = [SearchRecord::PersonType::PRIMARY]
    type_array << SearchRecord::PersonType::FAMILY if inclusive
    type_array << SearchRecord::PersonType::WITNESS if witness
    search_type = type_array.size > 1 ? { "$in" => type_array } : SearchRecord::PersonType::PRIMARY
    name_params["type"] = search_type

    if query_contains_wildcard?
        name_params["first_name"] = wildcard_to_regex(first_name.downcase) if first_name
        name_params["last_name"] = wildcard_to_regex(last_name.downcase) if last_name
  
        params["search_names"] =  { "$elemMatch" => name_params}
    
    else
      if fuzzy
        name_params["first_name"] = Text::Soundex.soundex(first_name) if first_name
        name_params["last_name"] = Text::Soundex.soundex(last_name) if last_name
  
        params["search_soundex"] =  { "$elemMatch" => name_params}
      else
        name_params["first_name"] = first_name.downcase if first_name
        name_params["last_name"] = last_name.downcase if last_name
  
        params["search_names"] =  { "$elemMatch" => name_params}
      end      
    end
    
    params
  end

  WILDCARD = /[?*]/

  def query_contains_wildcard?
    (first_name && first_name.match(WILDCARD)) || (last_name && last_name.match(WILDCARD)) 
  end
  

  def begins_with_wildcard(name_string)
    name_string.index(WILDCARD) == 0
  end
  
  def wildcard_to_regex(name_string)
    return name_string unless name_string.match(WILDCARD)
  
    trimmed = name_string.sub(/\**$/, '') # remove trailing * for performance
    regex_string = trimmed.gsub('?', '\w').gsub('*', '.*') #replace glob-style wildcards with regex wildcards
    
    begins_with_wildcard(name_string) ? /#{regex_string}/ : /^#{regex_string}/
  end

  def name_not_blank
    if last_name.blank? && !adequate_first_name_criteria? 
      errors.add(:first_name, "A forename and county must be part of your search if you have not entered a surname.")
    end
  end
  
  def adequate_first_name_criteria?
    !first_name.blank? && chapman_codes.length > 0
  end

  def wildcard_is_appropriate
    # allow promiscuous wildcards if place is defined
    if query_contains_wildcard?
      if place_search?
        # place_id is an adequate index -- all is well; do nothing
      else
        if last_name.match(WILDCARD)
          if last_name.index(WILDCARD) < 3
            errors.add(:last_name, "Three letters must precede any wildcard in a surname unless a specific place is also chosen.")
          end
        else
          # wildcard is in first name only -- no worries
        end
      end
    end
  end

  def county_is_valid
    if chapman_codes[0].nil? && !(record_type.present? && start_year.present? && end_year.present?)
      errors.add(:chapman_codes, "A date range and record type must be part of your search if you do not select a county.")
    end
    if chapman_codes.length > 3
      if !chapman_codes.eql?(["ALD", "GSY", "JSY", "SRK"])
       errors.add(:chapman_codes, "You cannot select more than 3 counties.") 
      end
    end
  end

  def date_range_is_valid
    if !start_year.blank? && !end_year.blank?
      if start_year.to_i > end_year.to_i
        errors.add(:end_year, "First year must precede last year.")
      end
    end
  end

  def radius_is_valid
    if search_nearby_places && places.count == 0
      errors.add(:search_nearby_places, "A Place must have been selected as a starting point to use the nearby option.")
    end
  end

  def wildcards_are_valid
    if first_name && begins_with_wildcard(first_name) && places.count == 0
      errors.add(:first_name, "A place must be selected if name queries begin with a wildcard")
    end      
  end

  def clean_blanks
    chapman_codes.delete_if { |x| x.blank? }
  end

  def radius_search?
    search_nearby_places
  end

  def all_radius_places
    all_places = []
    place_ids.each do |place_id|
      if radius_search?
        radius_places(place_id).each do |near_place|
          all_places << near_place
        end
      end
    end
    all_places.uniq
  end

  def can_be_narrowed?
    radius_search? && radius_factor > 2
  end

  def can_be_broadened?
    # radius_search? && radius_factor < 50 && result_count < 1000
    false
  end

  def radius_places(place_id)
    place = Place.find(place_id)
    place.places_near(radius_factor, place_system)
  end
  
end
