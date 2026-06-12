# frozen_string_literal: true

namespace :enterprise do
  desc 'Activate all Enterprise Edition features on a self-hosted instance'
  task setup: :environment do
    puts "\n#{('=' * 60)}"
    puts '  CHATWOOT ENTERPRISE SETUP'
    puts '=' * 60

    unless ChatwootApp.enterprise?
      puts "\n❌ Enterprise directory not found. Cannot activate enterprise features."
      puts "   Ensure the 'enterprise/' directory exists and DISABLE_ENTERPRISE is not set."
      exit 1
    end

    # Step 1: Set INSTALLATION_PRICING_PLAN to 'enterprise'
    set_installation_config('INSTALLATION_PRICING_PLAN', 'enterprise')

    # Step 2: Set DEPLOYMENT_ENV to 'self-hosted'
    set_installation_config('DEPLOYMENT_ENV', 'self-hosted')

    # Step 3: Set INSTALLATION_PRICING_PLAN_QUANTITY to current user count
    user_count = User.count
    set_installation_config('INSTALLATION_PRICING_PLAN_QUANTITY', user_count)

    # Step 4: Enable all premium feature flags on all accounts
    premium_features = load_premium_features
    default_features = load_default_enabled_features

    all_features_to_enable = (premium_features + default_features).uniq

    Account.find_in_batches do |accounts|
      accounts.each do |account|
        enabled_before = account.enabled_features.keys
        account.enable_features!(*all_features_to_enable)
        enabled_after = account.enabled_features.keys
        newly_enabled = enabled_after - enabled_before
        if newly_enabled.any?
          puts "   ✅ Account ##{account.id} (#{account.name}): enabled #{newly_enabled.join(', ')}"
        else
          puts "   ⏭️  Account ##{account.id} (#{account.name}): all features already enabled"
        end
      end
    end

    # Step 5: Clear GlobalConfig cache
    GlobalConfig.clear_cache
    puts '   🗑️  Cleared GlobalConfig cache'

    # Step 6: Remove Redis warning flag
    Redis::Alfred.delete(Redis::Alfred::CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING)
    puts '   🗑️  Cleared config reset warning flag'

    # Step 7: Update ACCOUNT_LEVEL_FEATURE_DEFAULTS so new accounts get premium features
    update_feature_defaults(premium_features)

    puts "\n#{('=' * 60)}"
    puts '  ✅ ENTERPRISE SETUP COMPLETE'
    puts '=' * 60
    puts "\n   Plan: #{ChatwootHub.pricing_plan}"
    puts "   Self-hosted enterprise: #{ChatwootApp.self_hosted_enterprise?}"
    puts "   Accounts updated: #{Account.count}"
    puts "\n   Restart Puma and Sidekiq for changes to take full effect."
    puts '=' * 60
  end

  desc 'Show current Enterprise Edition status'
  task status: :environment do
    puts "\n#{('=' * 60)}"
    puts '  CHATWOOT ENTERPRISE STATUS'
    puts '=' * 60

    puts "\n   Enterprise directory: #{ChatwootApp.enterprise? ? '✅ Present' : '❌ Missing'}"
    puts "   Self-hosted enterprise: #{ChatwootApp.self_hosted_enterprise? ? '✅ Yes' : '❌ No'}"
    puts "   Chatwoot Cloud: #{ChatwootApp.chatwoot_cloud? ? '✅ Yes' : '❌ No'}"

    deployment_env = InstallationConfig.find_by(name: 'DEPLOYMENT_ENV')&.value
    pricing_plan = InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN')&.value
    plan_quantity = InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN_QUANTITY')&.value

    puts "\n   INSTALLATION_PRICING_PLAN: #{pricing_plan || 'not set (defaults to community)'}"
    puts "   DEPLOYMENT_ENV: #{deployment_env || 'not set'}"
    puts "   INSTALLATION_PRICING_PLAN_QUANTITY: #{plan_quantity || 'not set'}"

    premium_features = load_premium_features
    puts "\n   Premium features defined: #{premium_features.join(', ')}"

    Account.find_each do |account|
      enabled_premium = premium_features.select { |f| account.feature_enabled?(f) }
      disabled_premium = premium_features - enabled_premium
      puts "\n   Account ##{account.id} (#{account.name}):"
      if enabled_premium.any?
        puts "     ✅ Enabled: #{enabled_premium.join(', ')}"
      end
      if disabled_premium.any?
        puts "     ❌ Disabled: #{disabled_premium.join(', ')}"
      end
    end

    puts "\n#{('=' * 60)}"
  end

  desc 'Disable all Enterprise premium features (revert to Community plan)'
  task disable: :environment do
    puts "\n#{('=' * 60)}"
    puts '  CHATWOOT ENTERPRISE DISABLE'
    puts '=' * 60

    premium_features = load_premium_features

    # Step 1: Set INSTALLATION_PRICING_PLAN back to 'community'
    set_installation_config('INSTALLATION_PRICING_PLAN', 'community')

    # Step 2: Disable all premium features on all accounts
    Account.find_in_batches do |accounts|
      accounts.each do |account|
        account.disable_features!(*premium_features)
        puts "   🔻 Account ##{account.id} (#{account.name}): disabled premium features"
      end
    end

    # Step 3: Clear caches
    GlobalConfig.clear_cache
    puts '   🗑️  Cleared GlobalConfig cache'

    puts "\n#{('=' * 60)}"
    puts '  ✅ ENTERPRISE FEATURES DISABLED'
    puts '=' * 60
    puts "\n   Plan: #{ChatwootHub.pricing_plan}"
    puts "   Restart Puma and Sidekiq for changes to take full effect."
    puts '=' * 60
  end

  private

  def set_installation_config(name, value)
    config = InstallationConfig.find_or_initialize_by(name: name)
    config.value = value
    config.locked = true
    config.save!
    puts "   💾 Set #{name} → #{value}"
  end

  def load_premium_features
    # Load from features.yml where premium: true
    features_list = YAML.safe_load(Rails.root.join('config/features.yml').read)
    features_list.select { |f| f['premium'] }.pluck('name')
  end

  def load_default_enabled_features
    # Load currently default-enabled features
    features_list = YAML.safe_load(Rails.root.join('config/features.yml').read)
    features_list.select { |f| f['enabled'] }.pluck('name')
  end

  def update_feature_defaults(premium_features)
    # Update ACCOUNT_LEVEL_FEATURE_DEFAULTS so new accounts automatically get premium features
    current_config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')

    if current_config.present?
      existing_features = current_config.value.map { |f| f.is_a?(Hash) ? f['name'] || f[:name] : f }
      new_defaults = (existing_features + premium_features).uniq.map do |name|
        { name: name, enabled: true }
      end
      current_config.update!(value: new_defaults)
      puts "   💾 Updated ACCOUNT_LEVEL_FEATURE_DEFAULTS (#{new_defaults.size} features)"
    else
      # Create from scratch with all features enabled
      all_features = load_default_enabled_features + premium_features
      defaults = all_features.uniq.map { |name| { name: name, enabled: true } }
      InstallationConfig.create!(
        name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS',
        value: defaults
      )
      puts "   💾 Created ACCOUNT_LEVEL_FEATURE_DEFAULTS (#{defaults.size} features)"
    end
  end
end