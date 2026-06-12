# frozen_string_literal: true

# Automatically configure Enterprise Edition features when SELF_HOSTED_ENTERPRISE=true.
#
# This initializer runs on every boot and ensures that:
# 1. INSTALLATION_PRICING_PLAN is set to 'enterprise' in the database
# 2. DEPLOYMENT_ENV is set to 'self-hosted'
# 3. All premium feature flags are enabled on every account
# 4. ACCOUNT_LEVEL_FEATURE_DEFAULTS includes premium features for new accounts
#
# Without this, a self-hosted instance would default to 'community' plan on first boot,
# and premium features would remain disabled even with SELF_HOSTED_ENTERPRISE=true.
#
# This is idempotent — safe to run on every boot without side effects.

return unless ENV.fetch('SELF_HOSTED_ENTERPRISE', 'false').casecmp?('true')
return unless ChatwootApp.enterprise?

Rails.application.config.after_initialize do
  # Guard against running before the database is ready (e.g., during db:create)
  unless ActiveRecord::Base.connection.table_exists?('installation_configs') &&
         ActiveRecord::Base.connection.table_exists?('accounts')
    Rails.logger.info('[SelfHostedEnterprise] Skipping — database tables not yet created')
    next
  end

  Rails.logger.info('[SelfHostedEnterprise] Configuring self-hosted enterprise instance...')

  begin
    # 1. Set INSTALLATION_PRICING_PLAN to 'enterprise'
    plan_config = InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_PRICING_PLAN')
    if plan_config.value != 'enterprise'
      plan_config.value = 'enterprise'
      plan_config.locked = true
      plan_config.save!
      Rails.logger.info('[SelfHostedEnterprise] Set INSTALLATION_PRICING_PLAN → enterprise')
    end

    # 2. Set DEPLOYMENT_ENV to 'self-hosted'
    deploy_config = InstallationConfig.find_or_initialize_by(name: 'DEPLOYMENT_ENV')
    if deploy_config.value != 'self-hosted'
      deploy_config.value = 'self-hosted'
      deploy_config.save!
      Rails.logger.info('[SelfHostedEnterprise] Set DEPLOYMENT_ENV → self-hosted')
    end

    # 3. Enable all premium feature flags on every account
    premium_features = YAML.safe_load(Rails.root.join('config/features.yml').read)
                          .select { |f| f['premium'] }
                          .pluck('name')

    enabled_features = YAML.safe_load(Rails.root.join('config/features.yml').read)
                          .select { |f| f['enabled'] }
                          .pluck('name')

    all_features_to_enable = (premium_features + enabled_features).uniq

    Account.find_in_batches do |accounts|
      accounts.each do |account|
        disabled_premium = premium_features.reject { |f| account.feature_enabled?(f) }
        if disabled_premium.any?
          account.enable_features!(*all_features_to_enable)
          Rails.logger.info("[SelfHostedEnterprise] Account ##{account.id} (#{account.name}): enabled #{disabled_premium.join(', ')}")
        end
      end
    end

    # 4. Update ACCOUNT_LEVEL_FEATURE_DEFAULTS so new accounts get premium features
    feature_defaults = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    if feature_defaults.present?
      existing_names = feature_defaults.value.map { |f| f.is_a?(Hash) ? f['name'] || f[:name] : f }
      missing = premium_features - existing_names
      if missing.any?
        new_defaults = (feature_defaults.value + missing.map { |n| { 'name' => n, 'enabled' => true } })
        feature_defaults.update!(value: new_defaults)
        Rails.logger.info("[SelfHostedEnterprise] Added #{missing.join(', ')} to ACCOUNT_LEVEL_FEATURE_DEFAULTS")
      end
    else
      all_defaults = all_features_to_enable.map { |n| { 'name' => n, 'enabled' => true } }
      InstallationConfig.create!(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS', value: all_defaults, locked: true)
      Rails.logger.info("[SelfHostedEnterprise] Created ACCOUNT_LEVEL_FEATURE_DEFAULTS with #{all_defaults.size} features")
    end

    # 5. Clear GlobalConfig cache so changes take effect immediately
    GlobalConfig.clear_cache
    Rails.logger.info('[SelfHostedEnterprise] Cleared GlobalConfig cache')

    # 6. Remove any stale config reset warning
    Redis::Alfred.delete(Redis::Alfred::CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING)

    Rails.logger.info('[SelfHostedEnterprise] Self-hosted enterprise configuration complete')
  rescue StandardError => e
    Rails.logger.error("[SelfHostedEnterprise] Error configuring enterprise: #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
  end
end