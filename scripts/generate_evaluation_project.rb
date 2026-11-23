#!/usr/bin/env ruby
require 'xcodeproj'
require 'json'
require_relative 'project_sdk_frameworks'
root = File.expand_path('..', __dir__)
destination = File.join(root, 'CritiqueEvaluation.xcodeproj')
raise 'Project already exists; preserve it and update deliberately' if File.exist?(destination)
project = Xcodeproj::Project.new(destination)
model = JSON.parse(File.read(File.join(root, 'Resources/EvaluationModel.json')))
target = project.new_target(:application, 'CritiqueEvaluation', :ios, '17.0')
target.product_name = 'CritiqueEvaluation'
package = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
package.relative_path = '.'
project.root_object.package_references << package
product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
product.product_name = 'CritiqueCore'; product.package = package
target.package_product_dependencies << product
core_link = project.new(Xcodeproj::Project::Object::PBXBuildFile)
core_link.product_ref = product
target.frameworks_build_phase.files << core_link
%w[App/LocalCoachEvaluationApp.swift].each do |path|
  target.source_build_phase.add_file_reference(project.main_group.new_file(path))
end
['Resources/Assets.xcassets', 'Resources/ThirdParty', 'Resources/EvaluationModel.json', 'Resources/CoachPolicy.txt', "local/models/#{model.fetch('filename')}"].each do |path|
  target.resources_build_phase.add_file_reference(project.main_group.new_file(path))
end
runtime = project.main_group.new_file('build/CritiqueRuntime.xcframework')
target.frameworks_build_phase.add_file_reference(runtime)
%w[Accelerate Metal MetalKit Foundation UIKit].each do |name|
  ref = project.frameworks_group.new_file("System/Library/Frameworks/#{name}.framework")
  target.frameworks_build_phase.add_file_reference(ref)
end
target.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.dash1971.critiqueai2.evaluation'
  settings['PRODUCT_NAME'] = 'CritiqueEvaluation'
  settings['SWIFT_VERSION'] = '5.0'
  settings['SWIFT_OBJC_BRIDGING_HEADER'] = 'Runtime/include/CoachBridge.h'
  settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'Critique AI 2.0 Eval'
  settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['CURRENT_PROJECT_VERSION'] = '1'
  settings['MARKETING_VERSION'] = '0.1.0'
  settings['OTHER_LDFLAGS'] = ['$(inherited)', '-lc++']
  settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  settings['SUPPORTED_PLATFORMS'] = 'iphoneos iphonesimulator'
  settings['ARCHS[sdk=iphonesimulator*]'] = 'x86_64'
end
CritiqueProject.normalize_system_frameworks(project)
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.save_as(destination, 'CritiqueEvaluation', true)
puts 'Created independent unsigned evaluation project; no team/credentials configured.'
