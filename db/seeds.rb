# loading installation configs
GlobalConfig.clear_cache
ConfigLoader.new.process

## Seeds productions
if Rails.env.production?
  # Setup Onboarding flow
  Redis::Alfred.set(Redis::Alfred::CHATWOOT_INSTALLATION_ONBOARDING, true)
end

## Seeds for Local Development
unless Rails.env.production?

  # Enables creating additional accounts from dashboard
  installation_config = InstallationConfig.find_by(name: 'CREATE_NEW_ACCOUNT_FROM_DASHBOARD')
  installation_config.value = true
  installation_config.save!
  GlobalConfig.clear_cache

  account = Account.create!(
    name: 'Acme Inc'
  )
  # El consultorio de Calendario opera en Colombia -- sin esto, el bucketing
  # de dias en Calendario::AppointmentStatsService cae a UTC por defecto.
  account.update!(reporting_timezone: 'Bogota')

  secondary_account = Account.create!(
    name: 'Acme Org'
  )

  user = User.new(name: 'John', email: 'john@acme.inc', password: 'Password1!', type: 'SuperAdmin')
  user.skip_confirmation!
  user.save!

  AccountUser.create!(
    account_id: account.id,
    user_id: user.id,
    role: :administrator
  )

  AccountUser.create!(
    account_id: secondary_account.id,
    user_id: user.id,
    role: :administrator
  )

  web_widget = Channel::WebWidget.create!(account: account, website_url: 'https://acme.inc')

  inbox = Inbox.create!(channel: web_widget, account: account, name: 'Acme Support')
  InboxMember.create!(user: user, inbox: inbox)

  contact_inbox = ContactInboxWithContactBuilder.new(
    source_id: user.id,
    inbox: inbox,
    hmac_verified: true,
    contact_attributes: { name: 'jane', email: 'jane@example.com', phone_number: '+2320000' }
  ).perform

  conversation = Conversation.create!(
    account: account,
    inbox: inbox,
    status: :open,
    assignee: user,
    contact: contact_inbox.contact,
    contact_inbox: contact_inbox,
    additional_attributes: {}
  )

  # sample email collect
  Seeders::MessageSeeder.create_sample_email_collect_message conversation

  Message.create!(content: 'Hello', account: account, inbox: inbox, conversation: conversation, sender: contact_inbox.contact,
                  message_type: :incoming)

  # sample location message
  #
  location_message = Message.new(content: 'location', account: account, inbox: inbox, sender: contact_inbox.contact, conversation: conversation,
                                 message_type: :incoming)
  location_message.attachments.new(
    account_id: account.id,
    file_type: 'location',
    coordinates_lat: 37.7893768,
    coordinates_long: -122.3895553,
    fallback_title: 'Bay Bridge, San Francisco, CA, USA'
  )
  location_message.save!

  # sample card
  Seeders::MessageSeeder.create_sample_cards_message conversation
  # input select
  Seeders::MessageSeeder.create_sample_input_select_message conversation
  # form
  Seeders::MessageSeeder.create_sample_form_message conversation
  # articles
  Seeders::MessageSeeder.create_sample_articles_message conversation
  # csat
  Seeders::MessageSeeder.create_sample_csat_collect_message conversation

  CannedResponse.create!(account: account, short_code: 'start', content: 'Hello welcome to chatwoot.')

  # Calendario: datos de prueba basados en el excel de agendas de urologia
  # (servicios, profesionales, disponibilidad y citas con estados variados)
  services = [
    Calendario::Service.create!(account: account, name: 'Consulta', duration_minutes: 20, color: '#4F81BD',
                                 kind: :consultation, base_price: 80_000),
    Calendario::Service.create!(account: account, name: 'Control', duration_minutes: 15, color: '#8064A2',
                                 kind: :control, base_price: 0),
    Calendario::Service.create!(account: account, name: 'Cistoscopia', duration_minutes: 15, color: '#9BBB59',
                                 kind: :procedure, included_sessions: 1, base_price: 150_000),
    Calendario::Service.create!(account: account, name: 'Urodinamia', duration_minutes: 45, color: '#F79646',
                                 kind: :procedure, included_sessions: 2, base_price: 220_000),
    Calendario::Service.create!(account: account, name: 'Vasectomia', duration_minutes: 30, color: '#C0504D',
                                 kind: :procedure, included_sessions: 1, base_price: 300_000)
  ]
  consulta, control, cistoscopia, urodinamia, vasectomia = services

  payers = [
    Calendario::Payer.create!(account: account, name: 'Particular', kind: :particular),
    Calendario::Payer.create!(account: account, name: 'Fomag', kind: :eps),
    Calendario::Payer.create!(account: account, name: 'Pijao Salud', kind: :eps),
    Calendario::Payer.create!(account: account, name: 'Los Rosales', kind: :eps),
    Calendario::Payer.create!(account: account, name: 'Sura Para Dos', kind: :eps),
    Calendario::Payer.create!(account: account, name: 'Sura Poliza', kind: :poliza)
  ]
  particular, fomag, pijao_salud, = payers

  # Tarifa especifica por EPS (copago) para consulta -- el resto de pagadores cae al base_price
  Calendario::ServicePrice.create!(service: consulta, payer: fomag, price: 20_000, copago: 20_000)
  Calendario::ServicePrice.create!(service: consulta, payer: pijao_salud, price: 15_000, copago: 15_000)
  Calendario::ServicePrice.create!(service: consulta, payer: particular, price: 80_000)

  urologia = Calendario::Specialty.create!(account: account, name: 'Urología')
  Calendario::Specialty.create!(account: account, name: 'Ginecología')

  professionals = ['Dr. Corrales', 'Dr. Devia', 'Dr. Velez', 'Dr. Gaviria', 'Dra. España'].map do |name|
    Calendario::Professional.create!(account: account, name: name, specialty: urologia)
  end

  professionals.each do |professional|
    [consulta, control, cistoscopia, urodinamia, vasectomia].each do |service|
      Calendario::ServiceProfessional.create!(professional: professional, service: service)
    end

    [['07:00', '12:00'], ['13:00', '17:00']].each do |(from, to)|
      Calendario::ProfessionalAvailability.create!(
        professional: professional,
        weekdays: [1, 2, 3, 4, 5],
        start_time: from,
        end_time: to,
        starts_on: Date.current - 30.days,
        ends_on: Date.current + 180.days
      )
    end
  end

  payer_by_eps = { 'Pijao Salud' => pijao_salud, 'Fomag' => fomag, 'Los Rosales' => payers.find { |p| p.name == 'Los Rosales' } }

  patients = [
    { name: 'Paciente de Prueba Uno', phone: '+573000000001', eps: 'Pijao Salud' },
    { name: 'Paciente de Prueba Dos', phone: '+573000000002', eps: 'Los Rosales' },
    { name: 'Paciente de Prueba Tres', phone: '+573000000003', eps: 'Los Rosales' },
    { name: 'Paciente de Prueba Cuatro', phone: '+573000000004', eps: 'Pijao Salud' },
    { name: 'Paciente de Prueba Cinco', phone: '+573000000005', eps: 'Fomag' },
    { name: 'Paciente de Prueba Seis', phone: '+573000000006', eps: 'Fomag' },
    { name: 'Paciente de Prueba Siete', phone: '+573000000007', eps: 'Los Rosales' },
    { name: 'Paciente de Prueba Ocho', phone: '+573000000008', eps: 'Fomag' },
    { name: 'Paciente de Prueba Nueve', phone: '+573000000009', eps: 'Fomag' },
    { name: 'Paciente de Prueba Diez', phone: '+573000000010', eps: 'Fomag' }
  ].map do |attrs|
    # La EPS es un dato del contacto, no de la cita -- se guarda aqui, no en
    # cada Calendario::Appointment que se cree para este paciente mas abajo.
    Contact.create!(account: account, name: attrs[:name], phone_number: attrs[:phone],
                     payer: payer_by_eps[attrs[:eps]], additional_attributes: { eps: attrs[:eps] })
  end

  # Historial: citas pasadas de esta semana con desenlace (asistio / no asistio)
  past_statuses = %i[attended attended no_show attended cancelled]
  professionals.each_with_index do |professional, p_index|
    2.times do |i|
      patient_index = (p_index * 2 + i) % patients.length
      patient = patients[patient_index]
      service = [consulta, cistoscopia].sample
      starts_at = (Date.current - (2 - i).days).to_time.change(hour: 8 + i * 2)
      appointment = Calendario::Appointment.new(
        account: account, professional: professional, service: service, contact: patient,
        starts_at: starts_at, ends_at: starts_at + service.duration_minutes.minutes
      )
      appointment.save!(validate: false)
      appointment.update_columns(status: Calendario::Appointment.statuses[past_statuses.sample])
    end
  end

  # Demo del "monedero" de sesiones: un procedimiento que ya se hizo (incluye
  # 1 control) le queda un credito disponible al primer paciente -- lo
  # consume la cita de control que se crea mas abajo en la agenda vigente.
  demo_patient = patients.first
  demo_procedure_appointment = Calendario::Appointment.new(
    account: account, professional: professionals.first, service: cistoscopia, contact: demo_patient,
    starts_at: Date.current.to_time.change(hour: 7),
    ends_at: Date.current.to_time.change(hour: 7, min: 15)
  )
  demo_procedure_appointment.save!(validate: false)
  demo_procedure_appointment.update_columns(status: Calendario::Appointment.statuses['attended'])
  account.calendario_contact_session_credits.create!(contact: demo_patient, granted_by_appointment: demo_procedure_appointment)

  # Agenda vigente: citas de hoy y de los proximos dias, pendientes/confirmadas
  professionals.each_with_index do |professional, p_index|
    3.times do |i|
      patient_index = (p_index + i) % patients.length
      patient = demo_patient if p_index.zero? && i.zero?
      patient ||= patients[patient_index]
      service = p_index.zero? && i.zero? ? control : [consulta, cistoscopia, urodinamia, vasectomia].sample
      day_offset = i + 1
      starts_at = (Date.current + day_offset.days).to_time.change(hour: 8 + i)
      Calendario::Appointment.create!(
        account: account, professional: professional, service: service, contact: patient,
        starts_at: starts_at, status: i.zero? ? :confirmed : :pending
      )
    end
  end

  # Documento de identidad en un par de contactos (demo del campo nuevo -- no
  # es obligatorio a nivel de modelo, solo en el formulario manual).
  patients[0].update!(document_type: :cc, identifier: '10000001', secondary_phone_number: '+573001112233')
  patients[1].update!(document_type: :cc, identifier: '10000002')

  # OpenDay: el doctor "abrio agenda" para estas fechas -- una con citas, una
  # sin ninguna (demo del estado vacio-pero-abierto), una en el pasado.
  professionals.each_with_index do |professional, p_index|
    account.calendario_open_days.create!(
      professional: professional, date: Date.current + (p_index + 2).days, time_window: :morning, opened_by: user
    )
  end
  account.calendario_open_days.create!(
    professional: professionals.first, date: Date.current + 10.days, time_window: :afternoon, opened_by: user
  )

  # Lista de espera: contactos sin fecha, esperando a que se abra agenda.
  patients[5..8].each_with_index do |patient, i|
    account.calendario_waitlist_entries.create!(
      contact: patient, professional: professionals[i % professionals.length],
      service: [consulta, cistoscopia].sample, status: :pending
    )
  end
end
