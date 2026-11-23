# Normalize system frameworks against the selected SDK, not a generator host's
# particular Xcode version.
module CritiqueProject
  SYSTEM_FRAMEWORKS = %w[Accelerate Metal MetalKit Foundation UIKit].freeze
  def self.normalize_system_frameworks(project)
    project.files.each do |file|
      next unless file.path&.end_with?('.framework')
      name = File.basename(file.path, '.framework')
      next unless SYSTEM_FRAMEWORKS.include?(name)
      file.path = "System/Library/Frameworks/#{name}.framework"
      file.source_tree = 'SDKROOT'
    end
  end
end
