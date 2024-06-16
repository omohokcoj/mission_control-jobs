require "mission_control/jobs/version"
require "mission_control/jobs/engine"

module MissionControl
  module Jobs
    class Engine < ::Rails::Engine
      isolate_namespace MissionControl::Jobs

      config.mission_control = ActiveSupport::OrderedOptions.new unless config.try(:mission_control)
      config.mission_control.jobs = ActiveSupport::OrderedOptions.new

      config.before_initialize do
        config.mission_control.jobs.applications = MissionControl::Jobs::Applications.new

        config.mission_control.jobs.each do |key, value|
          MissionControl::Jobs.public_send("#{key}=", value)
        end

        if MissionControl::Jobs.adapters.empty?
          MissionControl::Jobs.adapters << (config.active_job.queue_adapter || :async)
        end
      end

      initializer "mission_control-jobs.active_job.extensions" do
        ActiveSupport.on_load :active_job do
          include ActiveJob::Querying
          include ActiveJob::Executing
          include ActiveJob::Failed
          ActiveJob.extend ActiveJob::Querying::Root
        end
      end

      config.before_initialize do
        if MissionControl::Jobs.adapters.include?(:resque)
          require "resque/thread_safe_redis"
          ActiveJob::QueueAdapters::ResqueAdapter.prepend ActiveJob::QueueAdapters::ResqueExt
          Resque.prepend Resque::ThreadSafeRedis
        end

        if MissionControl::Jobs.adapters.include?(:solid_queue)
          ActiveJob::QueueAdapters::SolidQueueAdapter.prepend ActiveJob::QueueAdapters::SolidQueueExt
        end

        ActiveJob::QueueAdapters::AsyncAdapter.include MissionControl::Jobs::Adapter
      end

      config.after_initialize do |app|
        unless app.config.eager_load
          # When loading classes lazily (development), we want to make sure
          # the base host +ApplicationController+ class is loaded when loading the
          # Engine's +ApplicationController+, or it will fail to load the class.
          MissionControl::Jobs.base_controller_class.constantize
        end

        if MissionControl::Jobs.applications.empty?
          queue_adapters_by_name = MissionControl::Jobs.adapters.each_with_object({}) do |adapter, hsh|
            hsh[adapter] = ActiveJob::QueueAdapters.lookup(adapter).new
          end

          MissionControl::Jobs.applications.add(app.class.module_parent.name, queue_adapters_by_name)
        end
      end
    end
  end
end
