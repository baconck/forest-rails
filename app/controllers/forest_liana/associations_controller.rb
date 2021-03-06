module ForestLiana
  class AssociationsController < ForestLiana::ApplicationController
    if Rails::VERSION::MAJOR < 4
      before_filter :find_resource
      before_filter :find_association
    else
      before_action :find_resource
      before_action :find_association
    end

    def index
      begin
        getter = HasManyGetter.new(@resource, @association, params)
        getter.perform

        respond_to do |format|
          format.json { render_jsonapi(getter) }
          format.csv { render_csv(getter, @association.klass) }
        end
      rescue => error
        FOREST_LOGGER.error "Association Index error: #{error}\n#{format_stacktrace(error)}"
        internal_server_error
      end
    end

    def update
      begin
        updater = BelongsToUpdater.new(@resource, @association, params)
        updater.perform

        if updater.errors
          render serializer: nil, json: JSONAPI::Serializer.serialize_errors(
            updater.errors), status: 422
        else
          head :no_content
        end
      rescue => error
        FOREST_LOGGER.error "Association Update error: #{error}"\n#{error.backtrace}
        internal_server_error
      end
    end

    def associate
      begin
        associator = HasManyAssociator.new(@resource, @association, params)
        associator.perform

        head :no_content
      rescue => error
        FOREST_LOGGER.error "Association Associate error: #{error}\n#{format_stacktrace(error)}"
        internal_server_error
      end
    end

    def dissociate
      begin
        dissociator = HasManyDissociator.new(@resource, @association, params)
        dissociator.perform

        head :no_content
      rescue => error
        FOREST_LOGGER.error "Association Associate error: #{error}\n#{format_stacktrace(error)}"
        internal_server_error
      end
    end

    private

    def find_resource
      @resource = SchemaUtils.find_model_from_collection_name(params[:collection])

      if @resource.nil? || !@resource.ancestors.include?(ActiveRecord::Base)
        render serializer: nil, json: {status: 404}, status: :not_found
      end
    end

    def find_association
      # Rails 3 wants a :sym argument.
      @association = @resource.reflect_on_association(
        params[:association_name].try(:to_sym))

      # Only accept "many" associations
      if @association.nil? ||
        ([:belongs_to, :has_one].include?(@association.macro) &&
         params[:action] == 'index')
        render serializer: nil, json: {status: 404}, status: :not_found
      end
    end

    def resource_params
      ResourceDeserializer.new(@resource, params[:resource], true).perform
    end

    def is_sti_model?
      @is_sti_model ||= (@association.klass.inheritance_column.present? &&
        @association.klass.columns.any? { |column| column.name == @association.klass.inheritance_column })
    end

    def get_record record
      is_sti_model? ? record.becomes(@association.klass) : record
    end

    def render_jsonapi getter
      fields_to_serialize = fields_per_model(params[:fields], @association.klass)
      records = getter.records.map { |record| get_record(record) }

      if getter.includes.length > 0
        fields_to_serialize[@association.klass.name] += ",#{getter.includes.join(',')}"
      end

      json = serialize_models(
        records,
        include: getter.includes,
        fields: fields_to_serialize,
        count: getter.count,
        params: params
      )

      render serializer: nil, json: json
    end
  end
end
