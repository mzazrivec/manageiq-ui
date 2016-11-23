$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "manageiq/ui/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "manageiq-ui"
  s.version     = Manageiq::Ui::VERSION
  s.authors     = ["Martin Povolny"]
  s.email       = ["mpovolny@redhat.com"]
  s.homepage    = "http://www.manageiq.com"
  s.summary     = "Summary of Manageiq::Ui."
  s.description = "Description of Manageiq::Ui."
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]

  s.add_dependency "rails", "~> 5.0.0", ">= 5.0.0.1"
end
