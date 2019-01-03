module ActiveModel
  module Attributes
    module ModelTypes
      extend ActiveSupport::Concern

      included do
        type_class = Class.new(ActiveModel::Type::Value) do
          def cast(value)
            case value
            when self.class then value
            else self.class.parent.new(value)
            end
          end
        end

        array_type_class = Class.new(ActiveModel::Type::Value) do
          def cast(value)
            return [] if value.blank?
            value.map { |v| self.class.parent.const_get(:Type).new.cast(v) }
          end
        end

        const_set(:Type, type_class)
        const_set(:ArrayType, array_type_class)
      end
    end
  end
end
