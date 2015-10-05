require "spec_helper"
include ApplicationHelper

describe "layouts/listnav/_ems_cloud.html.haml" do
  before :each do
    set_controller_for_view("ems_cloud")
    assign(:panels, "ems_cloud_prop" => true, "ems_cloud_rel" => true)
    @settings = {:quadicons => {:ems => true}}
    view.stub(:truncate_length).and_return(23)
    ActionView::Base.any_instance.stub(:role_allows).and_return(true)
  end

  it "Favorites links use restful path" do
    record =  ManageIQ::Providers::Openstack::CloudManager.new(:name => "Test Cloud")
    assign(:record, record)
    record.stub(:flavors).and_return(5)
    render
    expect(response).to include "ems_cloud?display=flavors"
  end

  it "Instance links to use restful paths" do
    record = ManageIQ::Providers::Amazon::CloudManager.new(:name => "Test Cloud")
    assign(:record, record)
    record.stub(:flavors).and_return(14)
    render
    expect(response).to include "ems_cloud?display=flavors"
  end
end
