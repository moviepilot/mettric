require 'active_support/inflector'
require 'active_support/core_ext/hash/indifferent_access'
require 'active_support/core_ext/object/blank'
require 'riemann/client'

class Mettric::Client
  attr_reader :app, :host, :env

  def initialize(config = ::Mettric.config)
    @config = config || {}
    @riemann = Riemann::Client.new(
      host:    @config[:host]    || 'localhost',
      port:    @config[:port]    || 5555,
      timeout: @config[:timeout] || 5
    )

    self.app  = (@config[:app] || rails_app_name).to_s.underscore
    self.host = (@config[:reporting_host] || host_name).to_s.underscore
    self.env = (@config[:env] || rails_env).to_s.underscore


    if block_given?
      begin
        yield self
      ensure
        close
      end
    end
  end

  def app=(app_name)
    raise Mettric::MissingAppName, app.inspect if app_name.blank?
    @app = app_name
  end

  def host=(host_name)
    raise Mettric::MissingHostName if host_name.blank?
    @host = host_name
  end

  def env=(env)
    @env = env
  end

  def <<(payload)
    @riemann.tcp << standardize_payload(payload)
  rescue => e
    track_exception(e, payload)
  end

  def [](*args)
    @riemann[*args]
  end

  def close
    @riemann.close
  end

  def connected?
    @riemann.connected?
  end

  private

  def track_exception(e, payload)
    @riemann.tcp << { service: 'Mettric error', description: e.to_s }
    return unless Kernel.const_defined?(:NewRelic)
    NewRelic::Agent.notice_error(e, payload) rescue nil
  end

  def standardize_payload(payload)
    out = stringify(payload)
    raise Mettric::MissingService, out if out[:service].blank?

    out[:tags] = [out[:tags], :mettric].flatten.compact.uniq.map(&:to_s)
    out[:tags] << env if env.present?
    out[:metric] ||= 1

    out[:host] = host

    out[:service] = "#{app}.#{out[:service]}"
    out
  end

  def stringify(payload)
    out = payload.symbolize_keys
    out.each do |k,v|
      out[k] = v.to_s if v.is_a?(Symbol)
    end
  end

  def rails_app_name
    return unless Kernel.const_defined?(:Rails)
    Rails.application.class.parent.to_s.underscore
  end

  def rails_env
    return unless Kernel.const_defined?(:Rails)
    Rails.env
  end

  def host_name
    (ENV['METTRIC_REPORTING_HOST'] || `hostname`).to_s.chomp.underscore
  end
end
