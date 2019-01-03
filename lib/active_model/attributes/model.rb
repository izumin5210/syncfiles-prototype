require_relative './model_types'
require_relative './validations'

module ActiveModel
  module Attributes
    module Model
      extend ActiveSupport::Concern

      included do
        include ActiveModel::Attributes
        include ModelTypes
        include Validations
      end
    end
  end
end
