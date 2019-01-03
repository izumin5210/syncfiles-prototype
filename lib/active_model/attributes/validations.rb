module ActiveModel
  module Attributes
    module Validations
      extend ActiveSupport::Concern

      class_methods do
        def validates_attr(attr)
          type = attribute_types[attr.to_s]
          raise ArgumentError, "Unknown attribute: '#{attr}'" if type.blank?

          if type.cast(nil).kind_of?(Array)
            validates_each attr do |record, attr, value|
              value.each { |v| validate_attr(record, attr, v) }
            end
          else
            validates_each attr do |record, attr, value|
              validate_attr(record, attr, value)
            end
          end
        end

        private

        def validate_attr(record, attr, value)
          return if value.valid?
          value.errors.each do |sub_attr, e|
            record.errors.add(:"#{attr}.#{sub_attr}", e)
          end
        end
      end
    end
  end
end
