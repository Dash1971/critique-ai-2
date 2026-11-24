#!/usr/bin/env ruby
require 'xcodeproj'
require_relative 'project_sdk_frameworks'
root = File.expand_path('..', __dir__)
project_path = File.join(root, 'CritiqueEvaluation.xcodeproj')
project = Xcodeproj::Project.open(project_path)
abort 'Tracker target already exists; update it deliberately' if project.targets.any? { |t| t.name == 'CritiqueAI2' }
target = project.new_target(:application, 'CritiqueAI2', :ios, '17.0')
Dir.glob(File.join(root, 'App/Main/*.swift')).sort.each do |file|
  path = file.delete_prefix(root + '/')
  target.source_build_phase.add_file_reference(project.main_group.new_file(path))
end
assets = project.files.find { |file| file.path == 'Resources/Assets.xcassets' }
target.resources_build_phase.add_file_reference(assets || project.main_group.new_file('Resources/Assets.xcassets'))
package = project.root_object.package_references.find { |ref| ref.isa == 'XCLocalSwiftPackageReference' && ref.relative_path == '.' }
unless package
  package = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
  package.relative_path = '.'
  project.root_object.package_references << package
end
product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
product.product_name = 'CritiqueCore'
product.package = package
target.package_product_dependencies << product
build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
build_file.product_ref = product
target.frameworks_build_phase.files << build_file
target.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.dash1971.critiqueai2'
  settings['PRODUCT_NAME'] = 'CritiqueAI2'
  settings['SWIFT_VERSION'] = '5.0'
  settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'Critique AI 2.0'
  settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  settings['INFOPLIST_KEY_UISupportedInterfaceOrientations'] = 'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'
  settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  settings['CURRENT_PROJECT_VERSION'] = '2'
  settings['MARKETING_VERSION'] = '0.1.0'
  settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  settings['ARCHS[sdk=iphonesimulator*]'] = 'x86_64'
  settings['SUPPORTED_PLATFORMS'] = 'iphoneos iphonesimulator'
end
CritiqueProject.normalize_system_frameworks(project)
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target); scheme.set_launch_target(target)
scheme.save_as(project_path, 'CritiqueAI2', true)
puts 'Created independent unsigned tracker target; no Apple registration or upload.'
