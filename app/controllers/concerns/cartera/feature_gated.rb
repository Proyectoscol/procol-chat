module Cartera::FeatureGated
  extend ActiveSupport::Concern

  FEATURE = 'cartera'.freeze

  included do
    before_action :ensure_cartera_feature_enabled
  end

  private

  def ensure_cartera_feature_enabled
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?(FEATURE)
  end
end
