#!/usr/bin/env ruby
require 'xcodeproj'
require 'json'
require_relative 'project_sdk_frameworks'
root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'CritiqueEvaluation.xcodeproj'))
target = project.targets.find { |item| item.name == 'CritiqueAI2' }
abort 'Create the tracker target first' unless target
def reference(project, path)
  project.files.find { |file| file.path == path } || project.main_group.new_file(path)
end
source = 'App/Main/LocalCoachScreen.swift'
unless target.source_build_phase.files_references.any? { |file| file.path == source }
  target.source_build_phase.add_file_reference(reference(project, source))
end
model = JSON.parse(File.read(File.join(root, 'Resources/EvaluationModel.json')))
['Resources/EvaluationModel.json', 'Resources/CoachPolicy.txt', 'Resources/ThirdParty', "local/models/#{model.fetch('filename')}"].each do |path|
  unless target.resources_build_phase.files_references.any? { |file| file.path == path }
    target.resources_build_phase.add_file_reference(reference(project, path))
  end
end
['build/CritiqueRuntime.xcframework', 'System/Library/Frameworks/Accelerate.framework',
 'System/Library/Frameworks/Metal.framework', 'System/Library/Frameworks/MetalKit.framework',
 'System/Library/Frameworks/Foundation.framework', 'System/Library/Frameworks/UIKit.framework'].each do |path|
  unless target.frameworks_build_phase.files_references.compact.any? { |file| file.path == path }
    target.frameworks_build_phase.add_file_reference(reference(project, path))
  end
end
target.build_configurations.each do |configuration|
  configuration.build_settings['SWIFT_OBJC_BRIDGING_HEADER'] = 'Runtime/include/CoachBridge.h'
  flags = Array(configuration.build_settings['OTHER_LDFLAGS'])
  flags << '$(inherited)' unless flags.include?('$(inherited)')
  flags << '-lc++' unless flags.include?('-lc++')
  configuration.build_settings['OTHER_LDFLAGS'] = flags
end
CritiqueProject.normalize_system_frameworks(project)
project.save
puts 'Linked offline coach resources/runtime into the independent tracker; no signing or upload.'
