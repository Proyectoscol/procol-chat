##############################################
# Helpers to implement date range filtering to APIs
# Include in your controller or service class where params is available
##############################################

module DateRangeHelper
  def range
    return if params[:since].blank? || params[:until].blank?

    parse_date_time(params[:since])...parse_date_time(params[:until])
  end

  def parse_date_time(datetime)
    return datetime if datetime.is_a?(DateTime)
    return datetime.to_datetime if datetime.is_a?(Time) || datetime.is_a?(Date)

    # `strptime` requires a String. Query params arrive as strings already, but
    # params round-tripped through an ActiveJob (e.g. Sidekiq's JSON args)
    # preserve their original JSON type, so a unix timestamp can reach here as
    # an Integer.
    DateTime.strptime(datetime.to_s, '%s')
  end
end
