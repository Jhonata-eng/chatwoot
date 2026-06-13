module Enterprise::ChatwootHub
  ENTERPRISE_BASE_URL = 'https://hub.2.chatwoot.com'.freeze

  def base_url
    return ENV.fetch('CHATWOOT_HUB_URL', ENTERPRISE_BASE_URL) if Rails.env.development?

    ENTERPRISE_BASE_URL
  end

  # Self-hosted enterprise installations must not phone home to Chatwoot servers.
  # Each method below short-circuits when ChatwootApp.self_hosted_enterprise? is true,
  # preventing any outbound network request. DISABLE_TELEMETRY still works as a
  # fallback for non-self-hosted editions.

  def sync_with_hub
    return {} if ChatwootApp.self_hosted_enterprise?

    super
  end

  def register_instance(company_name, owner_name, owner_email)
    return if ChatwootApp.self_hosted_enterprise?

    super
  end

  def send_push(fcm_options)
    return if ChatwootApp.self_hosted_enterprise?

    super
  end

  def send_push_with_response(fcm_options)
    return if ChatwootApp.self_hosted_enterprise?

    super
  end

  def emit_event(event_name, event_data)
    return if ChatwootApp.self_hosted_enterprise?

    super
  end
end
