module ApplicationController::Timelines
  SELECT_EVENT_TYPE = [[_('Management Events'), 'timeline'], [_('Policy Events'), 'policy_timeline']].freeze
  SELECT_RESULT_TYPE = {_('Both') => 'both', _('True') => 'success', _('False') => 'failure'}.freeze
  EVENT_COLORS = ['#CD051C', '#005C25', '#035CB1', '#FF3106', '#FF00FF', '#000000'].freeze

  DateOptions = Struct.new(
    :daily,
    :days,
    :end,
    :hourly,
    :start,
    :typ
  ) do
    def update_from_params(params)
      self.typ = params[:tl_typ] if params[:tl_typ]
      self.days = params[:tl_days] if params[:tl_days]
      self.hourly = params[:miq_date_1] if params[:miq_date_1] && typ == 'Hourly'
      self.daily = params[:miq_date_1] if params[:miq_date_1] && typ == 'Daily'
    end

    def update_start_end(sdate, edate)
      if !sdate.nil? && !edate.nil?
        self.start = [sdate.year.to_s, (sdate.month - 1).to_s, sdate.day.to_s].join(", ")
        self.end = [edate.year.to_s, (edate.month - 1).to_s, edate.day.to_s].join(", ")
        self.hourly ||= [edate.month, edate.day, edate.year].join("/")
        self.daily ||= [edate.month, edate.day, edate.year].join("/")
      else
        self.start = self.end = nil
      end
      self.days ||= "7"
    end
  end

  ManagementEventsOptions = Struct.new(
    :level,
    :categories,
  ) do
    def update_from_params(params)
      self.level = params[:tl_fl_typ] == "critical" ? :critical : :detail
      self.categories = {}
      if params[:tl_categories]
        params[:tl_categories].each do |category|
          self.categories[events[category]] = {:display_name => category}
          self.categories[events[category]][:event_groups] = event_groups[events[category]][level]
        end
      end
    end

    def events
      @events ||= event_groups.each_with_object({}) do |egroup, hash|
        gname, list = egroup
        hash[list[:name].to_s] = gname
      end
    end

    def event_set
      event_set = []
      self.categories.each do |category|
        event_set.push(category.last[:event_groups])
      end
      event_set
    end

    def drop_cache
      @events = @event_groups = nil
    end

    private

    def build_filter(grp_name) # hidden fields to highlight bands in timeline
      arr = event_groups[grp_name][level.to_sym]
      arr.push(event_groups[grp_name][:critical]) if level == 'detail'
      "(" << arr.join(")|(") << ")"
    end

    def event_groups
      @event_groups ||= EmsEvent.event_groups
    end
  end

  PolicyEventsOptions = Struct.new(
    :applied_filters,
    :filters,
    :filters_all,
    :result
  ) do
    def update_from_params(params)
      self.result = params[:tl_result] if params[:tl_result]
      if params[:tl_fl_grp_all] == '1'
        self.filters_all = true
        events.keys.sort.each do |e|
          applied_filters.push(e)
        end
      elsif params[:tl_fl_grp_all] == 'null'
        self.filters_all = false
        self.applied_filters = []
        self.filters = Array.new(events.length) { '' }
      end
      # Look through the event type checkbox keys
      events.keys.sort.each_with_index do |e, i|
        ekey = "tl_fl_grp#{i + 1}__#{e.tr(' ', '_')}".to_sym
        if params[ekey] == '1' || (filters_all && params[ekey] != 'null')
          filters[i] = e
          applied_filters.push(e) unless applied_filters.include?(e) || self.filters_all = false
        elsif params[ekey] == 'null'
          self.filters_all = false
          filters[i] = nil
          applied_filters.delete(e)
        end
      end
    end

    def events
      @events ||= MiqEventDefinitionSet.all.each_with_object({}) do |event, hash|
        hash[event.description] = event.members.collect(&:id)
      end
    end

    def drop_cache
      @events = @fltr_cache = nil
    end

    def fltr(number)
      @fltr_cache ||= {}
      @fltr_cache[number] ||= build_filter(filters[number])
    end

    def event_set
      applied_filters.blank? ? [] : applied_filters.collect { |e| events[e] }
    end

    private

    def build_filter(grp_name) # hidden fields to highlight bands in timeline
      return '' if grp_name.blank?
      arr = []
      events[grp_name].each do |a|
        e = PolicyEvent.find_by_miq_event_definition_id(a.to_i)
        arr.push(e.event_type) unless e.nil?
      end
      arr.blank? ? '' : '(' << arr.join(')|(') << ')'
    end
  end

  Options = Struct.new(
    :date,
    :model,
    :mngt,
    :policy,
    :tl_show,
  ) do
    def initialize(*args)
      super
      self.date = DateOptions.new
      self.mngt = ManagementEventsOptions.new
      self.policy = PolicyEventsOptions.new
    end

    def management_events?
      tl_show == 'timeline'
    end

    def policy_events?
      tl_show == 'policy_timeline'
    end

    def evt_type
      management_events? ? :event_streams : :policy_events
    end

    def event_set
      (policy_events? ? policy : mngt).event_set
    end

    def drop_cache
      [policy, mngt].each(&:drop_cache)
    end
  end
end
