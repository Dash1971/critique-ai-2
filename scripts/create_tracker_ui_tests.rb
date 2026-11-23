#!/usr/bin/env ruby
require 'xcodeproj'
require_relative 'project_sdk_frameworks'
path = File.expand_path('../CritiqueEvaluation.xcodeproj', __dir__)
project = Xcodeproj::Project.open(path)
app = project.targets.find { |target| target.name == 'CritiqueAI2' }
abort 'Create the tracker target first' unless app
abort 'UI test target already exists; preserve it' if project.targets.any? { |target| target.name == 'TrackerUITests' }
test = project.new_target(:ui_test_bundle, 'TrackerUITests', :ios, '17.0')
test.source_build_phase.add_file_reference(project.main_group.new_file('Tests/TrackerUITests/TrackerUITests.swift'))
test.add_dependency(app)
test.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.dash1971.critiqueai2.uitests'
  settings['SWIFT_VERSION'] = '5.0'
  settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  settings['TEST_TARGET_NAME'] = 'CritiqueAI2'
  settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  settings['ARCHS[sdk=iphonesimulator*]'] = 'x86_64'
end
CritiqueProject.normalize_system_frameworks(project)
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_test_target(test)
scheme.set_launch_target(app)
scheme.save_as(path, 'CritiqueAI2', true)
puts 'Added simulator UI tests; no signing or upload.'
