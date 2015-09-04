module ReportFormatter
  module ChartCommon
    def slice_legend(string, limit = LEGEND_LENGTH)
      string.to_s.gsub(/\n/, ' ').truncate(limit)
    end

    def nonblank_or_default(value)
      value.blank? ? BLANK_VALUE : value.to_s
    end

    def mri
      options.mri
    end

    def build_document_header
      raise "Can't create a graph without a sortby column" if mri.sortby.nil? &&
          mri.db != "MiqReport" # MiqReport based charts are already sorted
      raise "Graph type not specified" if mri.graph.nil? ||
          (mri.graph.kind_of?(Hash) && mri.graph[:type].nil?)
    end

    def graph_options
      options.graph_options
    end

    def build_document_body
      return no_records_found_chart if mri.table.nil? || mri.table.data.blank?

      # find the highest chart value and set the units accordingly for large disk values (identified by GB in units)
      maxcols = 8
      divider = 1
      if graph_options[:units] == "GB" && !graph_options[:composite]
        maxval = 0
        mri.graph[:columns].each_with_index do |col, col_idx|
          next if col_idx >= maxcols
          newmax = mri.table.data.collect { |r| r[col].nil? ? 0 : r[col] }.sort.last
          maxval = newmax if newmax > maxval
        end
        if maxval > 10.gigabytes
          divider = 1.gigabyte
        elsif maxval > 10.megabytes
          graph_options[:units] = "MB"
          divider = 1.megabyte
        elsif maxval > 10.kilobytes
          graph_options[:units] = "KB"
          divider = 1.kilobyte
        else
          graph_options[:units] = "Bytes"
          graph_options[:decimals] = 0
          divider = 1
        end
        mri.title += " (#{graph_options[:units]})" unless graph_options[:units].blank?
      end

      fun = case graph_options[:chart_type]
            when :performance then :build_performance_chart # performance chart (time based)
            when :util_ts     then :build_util_ts_chart     # utilization timestamp chart (grouped columns)
            when :planning    then :build_planning_chart    # trend based planning chart
            else                                            # reporting charts
              mri.graph[:mode] == 'values' ? :build_reporting_chart_numeric : :build_reporting_chart
            end
      method(fun).call(maxcols, divider)
    end

    def build_document_footer
    end

    protected

    # C&U performance charts (Cluster, Host, VM based)
    def build_performance_chart_area(maxcols, divider)
      tz = mri.get_time_zone(Time.zone.name)
      nils2zero = false # Allow gaps in charts for nil values

  #### To do - Uncomment to handle long term averages
  #   if mri.extras && mri.extras[:long_term_averages]  # If averages are present
  #     mri.extras[:long_term_averages].keys.each do |avg_col|
  #       if mri.graph[:columns].include?(avg_col.to_s)
  #         mri.graph[:columns].push("avg__#{avg_col.to_s}")
  #       end
  #     end
  #   end
  ####

      mri.graph[:columns].each_with_index do |col, col_idx|
        next if col_idx >= maxcols
        allnil = true
        tip = graph_options[:trendtip] if col.starts_with?("trend") && graph_options[:trendtip]
        categories = []                      # Store categories and series counts in an array of arrays
        series = series_class.new
        mri.table.data.each_with_index do |r, d_idx|

          # Use timestamp or statistic_time (metrics vs ontap)
          rec_time = (r["timestamp"] || r["statistic_time"]).in_time_zone(tz)

          if mri.db.include?("Daily") || (mri.where_clause && mri.where_clause.include?("daily"))
            categories.push(rec_time.month.to_s + "/" + rec_time.day.to_s)
          elsif mri.extras[:realtime] == true
            categories.push(rec_time.strftime("%H:%M:%S"))
          else
            categories.push(rec_time.hour.to_s + ":00")
          end
  #           r[col] = nil if rec_time.day == 12  # Test code, uncomment to skip 12th day of the month

  #### To do - Uncomment to handle long term averages
  #       if col.starts_with?("avg__")
  #         val = mri.extras[:long_term_averages][col.split("__").last.to_sym]
  #       else
            val = r[col].nil? && (nils2zero) ? 0 : r[col]
  #       end
  ####

          val /= divider.to_f unless val.nil? || divider == 1
          if d_idx == mri.table.data.length - 1 && !tip.nil?
            series.push(:value => val, :tooltip => tip)
          else
            series.push(:value => val)
          end
          allnil = false if !val.nil? || nils2zero
        end
        series[-1] = 0 if allnil                    # XML/SWF Charts can't handle all nils, set the last value to 0
        add_axis_category_text(categories)

  #### To do - Uncomment to handle long term averages
  #     if col.starts_with?("avg__")
  #       head = "#{col.split("__").last.titleize}"
  #     else
          head = mri.graph[:legends] ? mri.graph[:legends][col_idx] : mri.headers[mri.col_order.index(col)] # Use legend overrides, if present
  #     end
  ####

        add_series(slice_legend(head), series)
      end
    end

    def rounded_value(value)
      return 0 if value.blank?
      value.round(graph_options[:decimals] || 0)
    end

    def build_performance_chart_pie(_maxcols, divider)
      col = mri.graph[:columns].first
      mri.table.sort_rows_by!(col, :order => :descending)
      categories = [] # Store categories and series counts in an array of arrays
      series = series_class.new
      cat_cnt = 0
      cat_total = mri.table.size
      mri.table.data.each do |r|
        cat = cat_cnt > 6 ? '<Other(1)>' : slice_legend(r["resource_name"])
        val = rounded_value(r[col]) / divider
        next if val == 0
        if cat.starts_with?("<Other(") && categories[-1].starts_with?("<Other(") # Are we past the top 10?
          categories[-1] = "<Other(#{cat_total - (cat_cnt - 1)})>" # Fix the <Other> category count
          series.add_to_value(-1, val) # Accumulate the series value
          next
        end
        categories.push(cat)
        cat_cnt += 1
        series.push(:value => val)
      end

      return no_records_found_chart if series.empty?

      add_axis_category_text(categories)
      add_series('', series)
    end

    def build_planning_chart(_maxcols, _divider)
      case mri.graph[:type]
      when "Column", "ColumnThreed" # Build XML for column charts
        categories = [] # Store categories and series counts in an array of arrays
        series     = []
        mri.graph[:columns].each_with_index do |col, col_idx|
          mri.table.data.each_with_index do |r, r_idx|
            break if r_idx > 9 || r[1].to_i == 0      # Skip if more than 10 rows or we find a row with second column (max vms count) of zero
            if col_idx == 0                           # First column is the category text
              categories.push((r_idx + 1).ordinalize) # Use 1st, 2nd, etc as the categories on the x axis
            else
              series[col_idx - 1] ||= {}
              series[col_idx - 1][:header] ||= mri.headers[mri.col_order.index(col)] # Add the series header
              series[col_idx - 1][:data] ||= series_class.new
              # If a max col size is set, limit the value to that size, else use the actual value
              val = r[col].to_i
              val = mri.graph[:max_col_size].to_i if mri.graph[:max_col_size] && val > mri.graph[:max_col_size].to_i
              tip = "#{Dictionary.gettext(mri.db_options[:options][:target_tags][:compute_type].to_s,
                                          :type     => :model,
                                          :notfound => :titleize)}: #{r[0]}"
              series[col_idx - 1][:data].push(:value => val, :tooltip => tip)
            end
          end
        end

  #     # Remove categories (and associated series values) that have all zero or nil values
  #     (categories.length - 1).downto(0) do |i|            # Go thru all cats
  #       t = 0.0
  #       series.each{|s| t += s[:data][i][:value].to_f}    # Add up the values for this cat across all series
  #       next if t != 0                                    # Not zero, keep this cat
  #       categories.delete_at(i)                           # Remove this cat
  #       series.each{|s| s[:data].delete_at(i)}            # Remove the data for this cat across all series
  #     end
  #
        # Remove any series where all values are zero or nil
        series.delete_if { |s| s[:data].sum == 0 }

        if series.empty?
          no_records_found_chart
          false
        else
          add_axis_category_text(categories)
          series.each { |s| add_series(s[:header], s[:data]) }
          true
        end
      end
    end

    def format_bytes_human_size_1
      {
        :function => {
          :name      => 'bytes_to_human_size',
          :precision => 1
        }
      }
    end

    # Utilization timestamp charts
    def build_util_ts_chart_column
      categories = []                     # Store categories and series counts in an array of arrays
      series     = []
      mri.graph[:columns].each_with_index do |col, col_idx|
        mri.table.data.each do |r|
          if col_idx == 0                 # First column is the category text
            categories.push(r[col])
          else
            series[col_idx - 1] ||= {}
            series[col_idx - 1][:header] ||= mri.headers[mri.col_order.index(col)] # Add the series header
            series[col_idx - 1][:data] ||= series_class.new
            tip_key = col + '_tip'
            tip = case r[0] # Override the formatting for certain column groups on single day percent utilization chart
                  when "CPU"
                    mri.format(tip_key, r[tip_key], :format => {
                      :function => {
                        :name      => "mhz_to_human_size",
                        :precision => "1"
                      }})
                  when "Memory"
                    mri.format(tip_key, r[tip_key].to_f * 1024 * 1024, :format => format_bytes_human_size_1)
                  when "Disk"
                    mri.format(tip_key, r[tip_key], :format => format_bytes_human_size_1)
                  else
                    mri.format(tip_key, r[tip_key])
                  end
            series[col_idx - 1][:data].push(
              :value   => mri.format(col, r[col]).to_f, # ?? .to_f ??
              :tooltip => tip
            )
          end
        end
      end

      # Remove categories (and associated series values) that have all zero or nil values
      (categories.length - 1).downto(0) do |i|
        sum = series.reduce(0.0) { |a, e| a + e[:data].value_at(i).to_f }
        next if sum != 0

        categories.delete_at(i)
        series.each { |s| s[:data].delete_at(i) } # Remove the data for this cat across all series
      end

      # Remove any series where all values are zero or nil
      series.delete_if { |s| s[:data].sum == 0 }

      if categories.empty?
        no_records_found_chart("No data found for the selected day")
        false
      else
        add_axis_category_text(categories)
        series.each { |s| add_series(s[:header], s[:data]) }
        true
      end
    end

    def keep_and_show_other
      # Show other sum value by default
      mri.graph.kind_of?(Hash) ? [mri.graph[:count].to_i, mri.graph[:other]] : [GRAPH_MAX_COUNT, true]
    end

    def build_reporting_chart_dim2
      (sort1, sort2) = mri.sortby
      save1 = save2 = counter = save1_nonblank = save2_nonblank = nil
      counts = {} # hash of hashes of counts
      mri.table.data.each_with_index do |r, d_idx|
        if d_idx == 0 || save1 != r[sort1].to_s
          counts[save1_nonblank][save2_nonblank] = counter unless d_idx == 0
          save1 = r[sort1].to_s
          save2 = r[sort2].to_s
          save1_nonblank = nonblank_or_default(save1)
          save2_nonblank = nonblank_or_default(save2)
          counts[save1_nonblank] = Hash.new(0)
          counter = 0
        else
          if save2 != r[sort2].to_s # only the second sort field changed, save the count
            counts[save1_nonblank][save2_nonblank] = counter
            save2 = r[sort2].to_s
            save2_nonblank = nonblank_or_default(save2)
            counter = 0
          end
        end
        counter += 1
      end
      # add the last key/value to the counts hash
      counts[save1_nonblank][save2_nonblank] = counter
      # We have all the counts, now we need to collect all of the . . .
      sort1_vals = []                  # sort field 1 values into an array and . . .
      sort2_vals_counts = Hash.new(0)  # sort field 2 values and counts into a Hash
      counts.each do |key1, hash1|
        sort1_vals.push(key1)
        hash1.each { |key2, count2| sort2_vals_counts[key2] += count2 }
      end
      sort2_vals = sort2_vals_counts.sort { |a, b| b[1] <=> a[1] } # Sort the field values by count size descending

      # trim and add axis_category_text to the chart
      sort1_vals.collect! { |value| slice_legend(value, LABEL_LENGTH) }
      add_axis_category_text(sort1_vals)

      # Now go through the counts hash again and put out a series for each sort field 1 hash of counts
      (keep, show_other) = keep_and_show_other

      # If there are more than keep categories Keep the highest counts
      other = keep < sort2_vals.length ? sort2_vals.slice!(keep..-1) : nil

      sort2_vals.each do |val2|
        series = counts.each_with_object(series_class.new) do |(key1, hash1), a|
          a.push(:value   => hash1[val2[0]],
                 :tooltip => "#{key1} / #{val2[0]}: #{hash1[val2[0]]}")
        end
        val2[0] = slice_legend(val2[0]) if val2[0].kind_of?(String)
        val2[0] = val2[0].to_s.gsub(/\\/, ' \ ')
        add_series(val2[0].to_s, series)
      end

      if other.present? && show_other # Sum up the other sort2 counts by sort1 value
        series = series_class.new
        counts.each do |key1, hash1|   # Go thru each sort1 key and hash count
          # Add in all of the remaining sort2 key counts
          ocount = other.reduce(0) { |a, e| a + hash1[e[0]] }
          series.push(:value   => ocount,
                      :tooltip => "#{key1} / Other: #{ocount}")
        end
        add_series(_("Other"), series)
      end
      counts
    end

    def data_column_name
      @data_column_name ||= (
        _model, col = mri.graph[:column].split('-', 2)
        col, aggreg = col.split(':', 2)
        aggreg.blank? ? col : "#{col}__#{aggreg}"
      )
    end

    # Options:
    #   sort1            -- labels
    #   data_column_name -- values
    #
    def build_numeric_chart_simple
      categories = []
      (sort1,) = mri.sortby
      (keep, show_other) = keep_and_show_other
      sorted_data = mri.table.data.sort_by { |row| row[data_column_name] || 0 }

      series = sorted_data.reverse.take(keep)
               .each_with_object(series_class.new(pie_type? ? :pie : :flat)) do |row, a|
        tooltip = row[sort1]
        tooltip = _('no value') if tooltip.blank?
        a.push(:value   => row[data_column_name],
               :tooltip => tooltip)
        categories.push([tooltip, row[data_column_name]])
      end

      if show_other
        other_sum = Array(sorted_data[0, sorted_data.length - keep])
                    .inject(0) { |sum, row| sum + row[data_column_name] }
        series.push(:value => other_sum, :tooltip => _('Other'))
        categories.push([_('Other'), other_sum])
      end

      # Pie charts put categories in legend, else in axis labels
      limit = pie_type? ? LEGEND_LENGTH : LABEL_LENGTH
      categories.collect! { |c| slice_legend(c[0], limit) }
      add_axis_category_text(categories)

      add_series(mri.headers[0], series)
    end

    def build_numeric_chart_grouped
      groups = mri.build_subtotals.reject { |k, _| k == :_total_ }

      match = mri.graph[:column].match(/^(\w*)-(\w*):(\w*)$/)
      (_model, column_name, aggreg) = match[1..3]
      aggreg = aggreg.to_sym

      (keep, show_other) = keep_and_show_other
      show_other &&= (aggreg == :total) # FIXME: we only support :total

      sorted_data = groups.sort_by { |_, data| data[aggreg][column_name] || 0 }

      categories = []
      series = sorted_data.reverse.take(keep)
               .each_with_object(series_class.new(pie_type? ? :pie : :flat)) do |(key, data), a|
        tooltip = key
        tooltip = _('no value') if key.blank?
        a.push(:value   => data[aggreg][column_name],
               :tooltip => key)
        categories.push([tooltip, data[aggreg][column_name]])
      end

      if show_other
        other_sum = Array(sorted_data[0, sorted_data.length - keep])
                    .inject(0) { |sum, (_key, row)| sum + row[aggreg][column_name] }

        series.push(:value => other_sum, :tooltip => _('Other'))
        categories.push([_('Other'), other_sum])
      end

      # Pie charts put categories in legend, else in axis labels
      limit = pie_type? ? LEGEND_LENGTH : LABEL_LENGTH
      categories.collect! { |c| slice_legend(c[0], limit) }
      add_axis_category_text(categories)

      add_series(mri.headers[0], series)
    end

    def build_numeric_chart_grouped_2dim
      (sort1, sort2) = mri.sortby
      (keep, show_other) = keep_and_show_other
      match = mri.graph[:column].match(/^([\w:]*)-([\w_]*):(\w*)$/)
      (_model, column_name, aggreg) = match[1..3]
      aggreg = aggreg.to_sym
      show_other &&= (aggreg == :total) # FIXME: we only support :total

      subtotals = mri.build_subtotals(true).reject { |k, _| k == :_total_ }

      # Group values by sort1
      # 3rd dimension in the chart is defined by sort2
      groups = mri.table.data.group_by { |row| row[sort1] }

      def_range_key2 = subtotals.keys.map { |key| key.split('__')[1] }.sort.uniq

      group_sums = groups.keys.each_with_object({}) do |key1, h|
        h[key1] = def_range_key2.inject(0) do |sum, key2|
          sub_key = "#{key1}__#{key2}"
          subtotals.key?(sub_key) ? sum + subtotals[sub_key][aggreg][column_name] : sum
        end
      end

      sorted_sums = group_sums.sort_by { |_key, sum| sum }

      selected_groups = sorted_sums.reverse.take(keep)

      cathegory_texts = selected_groups.collect do |key, _|
        label = slice_legend(key, LABEL_LENGTH)
        label = _('no value') if label.blank?
        label
      end
      cathegory_texts << _('Other') if show_other

      add_axis_category_text(cathegory_texts)

      if show_other
        other_groups = Array(sorted_sums[0, sorted_sums.length - keep])
        other = other_groups.each_with_object(Hash.new(0)) do |(key, _), o|
          groups[key].each { |row| o[row[sort2]] += row[column_name] }
        end
      end

      # For each value in sort2 column we create a series.
      sort2_values = mri.table.data.map { |row| row[sort2] }.uniq
      sort2_values.each do |val2|
        series = selected_groups.each_with_object(series_class.new) do |(key1, _), a|
          sub_key = "#{key1}__#{val2}"
          value = subtotals.key?(sub_key) ? subtotals[sub_key][aggreg][column_name] : 0

          a.push(:value   => value,
                 :tooltip => "#{key1} / #{val2}: #{value}")
        end

        series.push(:value   => other[val2],
                    :tooltip => "Other / #{val2}: #{other[val2]}") if show_other

        label = slice_legend(val2) if val2.kind_of?(String)
        label = label.to_s.gsub(/\\/, ' \ ')
        label = _('no value') if label.blank?
        add_series(label, series)
      end
      groups.keys.collect { |k| k.blank? ? _('no value') : k }
    end

    def pie_type?
      @pie_type ||= mri.graph[:type] =~ /^(Pie|Donut)/
    end

    def build_reporting_chart_other
      save_key   = nil
      counter    = 0
      categories = []                      # Store categories and series counts in an array of arrays
      mri.table.data.each_with_index do |r, d_idx|
        if d_idx > 0 && save_key != r[mri.sortby[0]]
          save_key = nonblank_or_default(save_key)
          categories.push([save_key, counter])    # Push current category and count onto the array
          counter = 0
        end
        save_key = r[mri.sortby[0]]
        counter += 1
      end
      # add the last key/value to the categories and series arrays
      save_key = nonblank_or_default(save_key)
      categories.push([save_key, counter])        # Push last category and count onto the array

      categories.sort! { |a, b| b.last <=> a.last }
      (keep, show_other) = keep_and_show_other
      if keep < categories.length                      # keep the cathegories w/ highest counts
        other = categories.slice!(keep..-1)
        ocount = other.reduce(0) { |a, e| a + e.last } # sum up and add the other counts
        categories.push(["Other", ocount]) if show_other
      end

      series = categories.each_with_object(
        series_class.new(pie_type? ? :pie : :flat)) do |cat, a|
        a.push(:value => cat.last, :tooltip => "#{cat.first}: #{cat.last}")
      end

      # Pie charts put categories in legend, else in axis labels
      limit = pie_type? ? LEGEND_LENGTH : LABEL_LENGTH
      categories.collect! { |c| slice_legend(c[0], limit) }
      add_axis_category_text(categories)
      add_series(mri.headers[0], series)
    end

    # C&U performance charts (Cluster, Host, VM based)
    def build_performance_chart(maxcols, divider)
      case mri.graph[:type]
      when "Area", "AreaThreed", "Line", "StackedArea",
           "StackedThreedArea", "ParallelThreedColumn"
        build_performance_chart_area(maxcols, divider)
      when "Pie", "PieThreed"
        build_performance_chart_pie(maxcols, divider)
      end
    end

    # Utilization timestamp charts
    def build_util_ts_chart(_maxcols, _divider)
      build_util_ts_chart_column if %w(Column ColumnThreed).index(mri.graph[:type])
    end

    def build_reporting_chart_numeric(_maxcols, _divider)
      if mri.group.nil?
        build_numeric_chart_simple
      else
        mri.dims == 2 ? build_numeric_chart_grouped_2dim : build_numeric_chart_grouped
      end
    end

    def build_reporting_chart(_maxcols, _divider)
      mri.dims == 2 ? build_reporting_chart_dim2 : build_reporting_chart_other
    end
  end
end
