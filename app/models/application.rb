# typed: strict
# frozen_string_literal: true

class Application < ApplicationRecord # rubocop:disable Style/Documentation
  include AASM

  has_many :deployments

  before_destroy :delete_deployments

  aasm column: :status, no_direct_assignment: true do # rubocop:disable Metrics/BlockLength,Lint/RedundantCopDisableDirective
    state :active, initial: true
    state :inactive, after: :notify_inactive
    state :invalid_config_error
    state :archived
    state :config_not_found
    state :merge_queue_disabled
    state :repo_not_accessible
    state :repo_not_found

    after_all_transitions :log_status_change

    # allow transition to inactive from any state
    event :inactivate do
      transitions to: :inactive, guard: proc { true }
    end

    event :update_status do
      transitions to: :active, guard: proc { |repo_state_resp| repo_status(repo_state_resp) == ACTIVE && deployment_config.present? }
      transitions to: :archived, guard: proc { |repo_state_resp| repo_status(repo_state_resp) == ARCHIVED }
      transitions to: :merge_queue_disabled, guard: proc { |repo_state_resp| repo_status(repo_state_resp) == MERGE_QUEUE_DISABLED }
      transitions to: :repo_not_found, guard: proc { |repo_state_resp| repo_status(repo_state_resp) == REPO_NOT_FOUND }
      transitions to: :repo_not_accessible, guard: proc { deployment_config.nil? && config_error.is_a?(RepoNotAccessible) }
      transitions to: :config_not_found, guard: proc { deployment_config.nil? && config_error.is_a?(ConfigNotFound) }
      transitions to: :invalid_config_error, guard: proc { deployment_config.nil? && config_error.is_a?(InvalidConfigError) }
      transitions to: :inactive, guard: proc { deployment_config.nil? && config_error.is_a?(AppNotAllowed) }
    end

    event :activate do
      transitions to: :active, guard: proc { true }
    end
  end

  ACTIVE = 0
  INACTIVE = 1
  INVALID_CONFIG_ERROR = 2
  ARCHIVED = 3
  CONFIG_NOT_FOUND = 4
  MERGE_QUEUE_DISABLED = 5
  REPO_NOT_ACCESSIBLE = 6
  REPO_NOT_FOUND = 7

  enum status: {
    active: 0,
    inactive: 1,
    invalid_config_error: 2,
    archived: 3,
    config_not_found: 4,
    merge_queue_disabled: 5,
    repo_not_accessible: 6,
    repo_not_found: 7
  }

  def log_status_change
    return unless persisted?
    return if status == aasm.to_state

    puts "changing from #{status} to #{aasm.to_state} (event: #{aasm.current_event})"
  end

  def notify_inactive
    puts "notifying that #{name} is inactive..."
  end

  class AppNotAllowed < StandardError # rubocop:disable Style/Documentation
    def initialize(msg = 'Application not allowed')
      super
    end
  end

  class InvalidConfigError < StandardError # rubocop:disable Style/Documentation
    def initialize(msg = 'Application not allowed')
      super
    end
  end

  class ConfigNotFound < StandardError # rubocop:disable Style/Documentation
    def initialize(msg = 'Application not allowed')
      super
    end
  end

  class RepoNotAccessible < StandardError # rubocop:disable Style/Documentation
    def initialize(msg = 'Repository not accessible')
      super
    end
  end

  def deployment_config
    return nil if @config_error

    puts 'STAGE: retrieving config...'
    @config ||= populate_config
  rescue StandardError => e
    puts 'STAGE: error retrieving config...'
    @config_error = e
    nil
  end

  def config_error
    @config_error ||= nil
  end

  def populate_config
    puts 'STAGE: populating config...'
    # current_second = Time.now.sec

    # case current_second % 10
    # when 0
    #   puts 'STAGE: app not allowed...'
    #   raise AppNotAllowed
    # when 1
    #   puts 'STAGE: invalid config error...'
    #   raise InvalidConfigError
    # when 2
    #   puts 'STAGE: config not found...'
    #   raise ConfigNotFound
    # end

    puts 'STAGE: returning config...'
    # { 'deployment' => { 'strategy' => 'kubernetes', 'prerequisites' => current_second.odd? } }
    { 'deployment' => { 'strategy' => 'kubernetes', 'prerequisites' => true } }
    raise InvalidConfigError
  end

  def repo_status(repo_status_resp = nil)
    @repo_status ||= populate_repo_status(repo_status_resp)
  end

  def populate_repo_status(repo_status_resp = nil) # rubocop:disable Metrics/MethodLength,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    puts 'STAGE: populating repo status...'
    repo_state = nil
    unless repo_status_resp.nil?
      puts 'STAGE: repo status response provided...'
      puts "STAGE: repo_status #{repo_status_resp}"
      if !repo_status_resp[:repo_found]
        repo_state = REPO_NOT_FOUND
      elsif repo_status_resp[:is_archived]
        repo_state = ARCHIVED
      elsif pipelines_enabled && !repo_status_resp[:merge_queue_id].nil?
        repo_state = ACTIVE
      elsif pipelines_enabled && repo_status_resp[:merge_queue_id].nil?
        repo_state = MERGE_QUEUE_DISABLED
      elsif !pipelines_enabled
        repo_state = ACTIVE
      end
    end
    puts "STAGE: returning repo state #{repo_state}..."
    repo_state
  end

  def pipelines_enabled
    true
  end

  def create_deployment
    puts 'STAGE: creating deployment...'
    deployments.create!(strategy: config['deployment']['strategy'])
  end

  def delete_deployments
    puts 'STAGE: deleting deployments...'
    deployments.destroy_all
  end
end
