#!/usr/bin/env ruby
require 'json'
require 'digest'
require 'xcodeproj'
root = File.expand_path('..', __dir__)
filename = ARGV.fetch(0) { abort 'Provide a filename from the pinned model manifest' }
manifest = JSON.parse(File.read(File.join(root, 'Docs/20261123_v0_local_model_candidates.json')))
model = manifest.fetch('candidates').find { |m| m['filename'] == filename }
abort 'Unknown model; pin and verify its artifact first' unless model
weights = File.join(root, 'local/models', filename)
abort 'Model bytes or SHA-256 do not match' unless File.size(weights) == model.fetch('bytes') && Digest::SHA256.file(weights).hexdigest == model.fetch('sha256_publisher_metadata')
project = Xcodeproj::Project.open(File.join(root, 'CritiqueEvaluation.xcodeproj'))
target = project.targets.find { |t| t.name == 'CritiqueEvaluation' }
references = target.resources_build_phase.files_references.select { |ref| ref.path&.end_with?('.gguf') }
abort 'Expected exactly one evaluation weight resource' unless references.count == 1
references.first.path = "local/models/#{filename}"
references.first.name = filename
unless target.resources_build_phase.files_references.any? { |ref| ref.path == 'Resources/EvaluationModel.json' }
  target.resources_build_phase.add_file_reference(project.main_group.new_file('Resources/EvaluationModel.json'))
end
unless target.resources_build_phase.files_references.any? { |ref| ref.path == 'Resources/CoachPolicy.txt' }
  target.resources_build_phase.add_file_reference(project.main_group.new_file('Resources/CoachPolicy.txt'))
end
spec = {name: model.fetch('upstream_model'), filename: filename,
        sha256: model.fetch('sha256_publisher_metadata'), bytes: model.fetch('bytes'),
        quality_status: 'Evaluation only; not approved for coaching release'}
File.write(File.join(root, 'Resources/EvaluationModel.json'), JSON.pretty_generate(spec) + "\n")
project.save
puts 'Selected one verified evaluation artifact; no signing, upload or model approval.'
