# frozen_string_literal: true

class CustomExceptions::Team::MirroredFromInbox < CustomExceptions::Base
  def message
    'This team mirrors an inbox\'s collaborators and cannot be edited manually. ' \
      'Manage its members from the inbox\'s Collaborators settings instead.'
  end

  def to_hash
    { error: message }
  end

  def http_status
    :unprocessable_entity
  end
end
