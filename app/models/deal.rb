class Deal < ActiveRecord::Base
  unloadable

  def self.contact_name(id, resources, organization=false)
    resources.each do |resource|
      return resource.name if resource.id == id && resource.is_organization == organization
    end
  end

  def self.user_name(id, resources)
    resources.each do |resource|
      return resource.name if resource.id == id
    end
  end
end
