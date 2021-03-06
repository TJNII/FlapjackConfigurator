#!/usr/bin/env ruby

require_relative 'flapjack_object_base.rb'
require_relative 'flapjack_media.rb'
require_relative 'flapjack_pagerduty.rb'
require_relative 'flapjack_notification_rule.rb'

module FlapjackConfigurator
  # Class representing a Flapjack contact
  class FlapjackContact < FlapjackObjectBase
    attr_reader :media

    def initialize(my_id, current_config, diner, logger, current_media = [], current_notification_rules = [])
      @diner = diner
      @logger = logger
      super(my_id, current_config, diner.method(:contacts), diner.method(:create_contacts), diner.method(:update_contacts), diner.method(:delete_contacts), logger, 'contact')

      # Select our media out from a premade hash of all media built from a single API call
      @media = current_media.select { |m| m.config[:links][:contacts].include? id }

      # Select notification rules the same way.
      @notification_rules = current_notification_rules.select { |m| m.config[:links][:contacts].include? id }
    end

    # Update all the things
    def update(config_obj)
      ret_val = false
      ret_val = true if update_attributes(config_obj)
      ret_val = true if update_entities(config_obj)
      ret_val = true if update_media(config_obj)
      ret_val = true if update_notification_rules(config_obj)
      return ret_val
    end

    # Define our own _create as it doesn't use an ID
    def _create(config)
      fail("Object #{id} exists") if @obj_exists
      # AFAIK there is not an easy way to convert hash keys to symbols outside of Rails
      config.each { |k, v| @config[k.to_sym] = v }
      @logger.info("Creating contact #{id} with config #{@config}")
      fail "Failed to create contact #{id}" unless @create_method.call([@config])
      _reload_config

      # Creating an entity auto generates notification rules
      # Regenerate the notification rules
      @notification_rules = []
      @config[:links][:notification_rules].each do |nr_id|
        @notification_rules << FlapjackNotificationRule.new(nr_id, nil, @diner, @logger)
      end
    end

    # Update attributes from the config, creating the contact if needed
    # (Chef definition of "update")
    # Does not handle entites or notifications
    def update_attributes(config_obj)
      @logger.debug("Updating attributes for contact #{id}")
      if @obj_exists
        return _update(config_obj.contact_config(id)['details'])
      else
        _create(config_obj.contact_config(id)['details'])
        return true
      end
    end

    # Update entities for the contact, creating or removing as needed
    def update_entities(config_obj)
      fail("Contact #{id} doesn't exist yet") unless @obj_exists
      @logger.debug("Updating entities for contact #{id}")

      wanted_entities = config_obj.entity_map.entities_for_contact(id)
      current_entities = @config[:links][:entities]
      ret_val = false

      (wanted_entities - current_entities).each do |entity_id|
        @logger.info("Associating entity #{entity_id} to contact #{id}")
        fail("Failed to add entity #{entity_id} to contact #{id}") unless @diner.update_contacts(id, add_entity: entity_id)
        ret_val = true
      end

      (current_entities - wanted_entities).each do |entity_id|
        @logger.info("Removing entity #{entity_id} from contact #{id}")
        fail("Failed to remove entity #{entity_id} from contact #{id}") unless @diner.update_contacts(id, remove_entity: entity_id)
        ret_val = true
      end

      _reload_config
      return ret_val
    end

    # Update the media for the contact
    def update_media(config_obj)
      @logger.debug("Updating media for contact #{id}")
      media_config = config_obj.media(id)
      ret_val = false

      media_config_types = media_config.keys
      @media.each do |media_obj|
        if media_config_types.include? media_obj.type
          ret_val = true if media_obj.update(media_config[media_obj.type])
          # Delete the ID from the type array. This will result in media_config_types being a list of types that need to be created at the end of the loop
          media_config_types.delete(media_obj.type)
        else
          media_obj.delete
          ret_val = true
        end
      end

      # Delete outside the loop as deleting inside the loop messes up the each iterator
      @media.delete_if { |obj| !obj.obj_exists }

      media_config_types.each do |type|
        # Pagerduty special case again
        # TODO: Push this back up so that the if isn't done here
        if type == 'pagerduty'
          media_obj = FlapjackPagerduty.new(nil, @diner, @logger)
          media_obj.create(id, media_config[type])
        else
          media_obj = FlapjackMedia.new(nil, @diner, @logger)
          media_obj.create(id, type, media_config[type])
        end
        @media << media_obj
      end

      return ret_val || media_config_types.length > 0
    end

    def update_notification_rules(config_obj)
      @logger.debug("Updating notification rules for contact #{id}")
      nr_config = config_obj.notification_rules(id)
      nr_config_ids = nr_config.keys
      ret_val = false

      @notification_rules.each do |nr_obj|
        if nr_config_ids.include? nr_obj.id
          ret_val = true if nr_obj.update(nr_config[nr_obj.id])
          # Delete the ID from the type array. This will result in nr_config_ids being a list of types that need to be created at the end of the loop
          nr_config_ids.delete(nr_obj.id)
        else
          nr_obj.delete
          ret_val = true
        end
      end

      # Delete outside the loop as deleting inside the loop messes up the each iterator
      @notification_rules.delete_if { |obj| !obj.obj_exists }

      nr_config_ids.each do |nr_id|
        nr_obj = FlapjackNotificationRule.new(nr_id, nil, @diner, @logger)
        nr_obj.create(id, nr_config[nr_id])
        @notification_rules << (nr_obj)
      end

      return ret_val || nr_config_ids.length > 0
    end
  end
end
