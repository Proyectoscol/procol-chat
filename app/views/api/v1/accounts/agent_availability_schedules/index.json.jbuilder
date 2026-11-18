json.array! @agent_availability_schedules do |schedule|
  json.partial! 'api/v1/models/agent_availability_schedule', formats: [:json], resource: schedule
end
