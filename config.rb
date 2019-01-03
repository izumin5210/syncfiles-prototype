class Config
  include ActiveModel::Model
    include ActiveModel::Attributes::Model

  class Src
    include ActiveModel::Model
    include ActiveModel::Attributes::Model

    attribute :path, :string

    validates :path, presence: true
  end

  class Dest
    include ActiveModel::Model
    include ActiveModel::Attributes::Model

    attribute :repo, :string
    attribute :path, :string

    validates :repo, presence: true
    validates :path, presence: true
  end

  class Entry
    include ActiveModel::Model
    include ActiveModel::Attributes::Model

    attribute :src, Src::Type.new
    attribute :dests, Dest::ArrayType.new

    validates_attr :src
    validates_attr :dests
  end

  attribute :entries, Entry::ArrayType.new

  validates_attr :entries
end
