class TreeBuilderProtect < TreeBuilder
  has_kids_for Hash, [:x_get_tree_hash_kids]

  def initialize(name, type, sandbox, build = true, data)
    @data = data
    super(name, type, sandbox, build)
  end

  private

  def tree_init_options(_tree_name)
    {:full_ids => false, :add_root => false, :lazy => false}
  end

  def set_locals_for_render
    locals = super
    locals.merge!(:id_prefix                   => 'protect_',
                  :checkboxes                  => true,
                  :onclick                     => false,
                  :open_close_all_on_dbl_click => true,
                  :oncheck                     => "miqOnCheckProtect",
                  :check_url                   =>  "/#{@data[:controller_name]}/protect/ " # TODO "/#{request.parameters["controller"]}/protect/"
    )
  end

  def root_options
    []
  end

  def x_get_tree_roots(count_only = false, _options)
    nodes = MiqPolicySet.all.sort_by { |profile| profile.description.downcase }.map do |profile|
      { :id       => "policy_profile_#{profile.id}",
        :text     => profile.description,
        :image    => "policy_profile#{profile.active? ? "" : "_inactive"}",
        :tip      => profile.description,
        :select   => @data[:new][profile.id] == @data[:pol_items].length,
        :addClass => @data[:new][profile.id] != @data[:current][profile.id] ? "cfme-blue-bold-node" : '',
        :children => profile.members
      }
    end
    count_only_or_objects(count_only, nodes)
  end

  def x_get_tree_hash_kids(parent, count_only)
    nodes = parent[:children].map do |policy|
      {:id       => "policy_#{policy.id}",
       :text     => "<b>#{ui_lookup(:model => policy.towhat)} #{policy.mode.capitalize}:</b> #{policy.description}".html_safe,
       :image    => "miq_policy_#{policy.towhat.downcase}#{policy.active ? "" : "_inactive"}",
       :tip      => policy.description,
       :hideCheckbox => true,
       :children => []
      }
    end
    count_only_or_objects(count_only, nodes)
  end
end