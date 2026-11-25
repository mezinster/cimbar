#!/usr/bin/env ruby
# frozen_string_literal: true

# Configures app/ios/Runner.xcodeproj beyond what `flutter create` generates.
# There is no Xcode in the dev environment, so every project edit lives here,
# reviewable and re-runnable (idempotent). Needs the xcodeproj gem
# (`gem install xcodeproj`). Run from anywhere:
#
#   ruby app/ios/tool/configure_xcode_project.rb
#
# 1. Localized permission prompts: Runner/<lang>.lproj/InfoPlist.strings as a
#    variant group in Runner's resources, and the languages in knownRegions.
# 2. Runner's App Group entitlements (share_handler hands files over through
#    group.com.nfcarchiver.cimbarscanner, named by the AppGroupId key in both
#    Info.plists; share_handler's default, group.<bundle id>, belongs to
#    another team).
# 3. The ShareExtension target (share_handler), embedded in Runner.
# 4. The deployment target, on the project and on every target that pins one.
# 5. Runner/PrivacyInfo.xcprivacy in Runner's resources (App Store Connect
#    requires an app-level privacy manifest).
# 6. Runner/PhotoEncoder.swift (the native photo channel) in Runner's sources.
require 'xcodeproj'

IOS = File.expand_path('..', __dir__)
APP_ID = 'com.nfcarchiver.cimbar'
EXT = 'ShareExtension'
LANGS = %w[en ru uk tr ka pl be].freeze

project = Xcodeproj::Project.open(File.join(IOS, 'Runner.xcodeproj'))
runner = project.targets.find { |t| t.name == 'Runner' } or abort('no Runner target')
runner_group = project.main_group['Runner'] or abort('no Runner group')
# App Store Connect warns on every upload targeting less than iOS 15 and refuses
# them from April 2027 (file_picker_darwin 2.x alone would need 14). Every device
# that ran iOS 14 runs 15. The Podfile's `platform :ios` must match.
DEPLOYMENT = '15.0'

# --- 1. localized InfoPlist.strings -------------------------------------------
project.root_object.known_regions = (project.root_object.known_regions + LANGS).uniq
variant = runner_group.children.find { |c| c.isa == 'PBXVariantGroup' && c.name == 'InfoPlist.strings' }
unless variant
  variant = runner_group.new_variant_group('InfoPlist.strings')
  runner.resources_build_phase.add_file_reference(variant, true)
end
# Add each language that is missing, so a new app language only needs its
# lproj file and an entry in LANGS.
LANGS.each do |lang|
  next if variant.children.any? { |c| c.name == lang }
  ref = variant.new_reference("#{lang}.lproj/InfoPlist.strings")
  ref.name = lang
end

# --- 2. Runner entitlements -----------------------------------------------------
unless runner_group.files.any? { |f| f.path == 'Runner.entitlements' }
  runner_group.new_reference('Runner.entitlements')
end
runner.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

# --- 3. ShareExtension target ---------------------------------------------------
unless project.targets.any? { |t| t.name == EXT }
  ext = project.new_target(:app_extension, EXT, :ios, DEPLOYMENT, nil, :swift)
  group = project.main_group.new_group(EXT, EXT)
  swift = group.new_reference('ShareViewController.swift')
  group.new_reference('Info.plist')
  group.new_reference("#{EXT}.entitlements")
  debug_xcconfig = group.new_reference('Debug.xcconfig')
  release_xcconfig = group.new_reference('Release.xcconfig')
  ext.add_file_references([swift])

  # One configuration per project configuration (Debug, Release, Profile).
  project.build_configurations.map(&:name).each do |name|
    next if ext.build_configuration_list[name]

    ext.add_build_configuration(name, name == 'Debug' ? :debug : :release)
  end

  ext.build_configurations.each do |config|
    config.base_configuration_reference = config.name == 'Debug' ? debug_xcconfig : release_xcconfig
    s = config.build_settings
    s['PRODUCT_BUNDLE_IDENTIFIER'] = "#{APP_ID}.#{EXT}"
    s['PRODUCT_NAME'] = '$(TARGET_NAME)'
    s['INFOPLIST_FILE'] = "#{EXT}/Info.plist"
    s['GENERATE_INFOPLIST_FILE'] = 'NO'
    s['CODE_SIGN_ENTITLEMENTS'] = "#{EXT}/#{EXT}.entitlements"
    s['SWIFT_VERSION'] = '5.0'
    s['TARGETED_DEVICE_FAMILY'] = '1,2'
    s['SKIP_INSTALL'] = 'YES'
    s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  end

  embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.symbol_dst_subfolder_spec = :plug_ins
  build_file = embed.add_file_reference(ext.product_reference, true)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  # Flutter's "Thin Binary" script must run after the extension is embedded,
  # or Xcode reports a dependency cycle in Runner.
  thin = runner.build_phases.find { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
  if thin
    runner.build_phases.delete(embed)
    runner.build_phases.insert(runner.build_phases.index(thin), embed)
  end
  runner.add_dependency(ext)
end

# --- 4. Deployment target -------------------------------------------------------
# Runs every time (outside any creation guard) so an existing project is bumped
# too: the project-level configurations plus every target that pins its own.
(project.build_configurations + project.targets.flat_map(&:build_configurations)).each do |config|
  s = config.build_settings
  next unless project.build_configurations.include?(config) || s.key?('IPHONEOS_DEPLOYMENT_TARGET')

  s['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT
end

# --- 5. Privacy manifest ---------------------------------------------------------
# A file that is not in the Resources phase never reaches the bundle.
privacy = runner_group.files.find { |f| f.path == 'PrivacyInfo.xcprivacy' } ||
          runner_group.new_reference('PrivacyInfo.xcprivacy')
unless runner.resources_build_phase.files_references.include?(privacy)
  runner.resources_build_phase.add_file_reference(privacy, true)
end

# --- 6. PhotoEncoder.swift ------------------------------------------------------
unless runner_group.files.any? { |f| f.path == 'PhotoEncoder.swift' }
  runner.add_file_references([runner_group.new_reference('PhotoEncoder.swift')])
end

project.save
puts "configured #{File.join(IOS, 'Runner.xcodeproj')}"
