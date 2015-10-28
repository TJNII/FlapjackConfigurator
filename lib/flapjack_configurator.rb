#!/usr/bin/env ruby

require 'flapjack-diner'
require 'logger'
require 'flapjack_configurator/flapjack_config'
require 'flapjack_configurator/version'

# Flapjack Configuration Module
module FlapjackConfigurator
  # Method to configure flapjack
  def self.configure_flapjack(config, api_base_url = 'http://127.0.0.1:3081', logger = nil)
    Flapjack::Diner.base_uri(api_base_url)
    unless logger
      logger = Logger.new(STDOUT)
      logger.level = Logger::INFO
    end

    # The underlying classes treat the Flapjack::Diner module as if it is a class.
    # This was done as it was fairly natural and will allow Flapjack::Diner to be
    # replaced or wrapped very easily in the future.
    config_obj = FlapjackConfig.new(config, Flapjack::Diner, logger)

    # Update the contacts
    # This will update media, PD creds, notification rules, and entity associations
    #   as they're associated to the contact.
    return config_obj.update_contacts
  end

  # Simple helper to return the gem version
  def self.version
    return VERSION
  end
end
