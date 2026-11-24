# Arma el .zip descargable con todos los datos de una cuenta (ver
# Calendario::AccountDataTransferSpec para el detalle exacto de que se
# exporta y en que orden). Un solo archivo: manifest.json + data.json +
# carpeta attachments/ con los bytes reales de cada adjunto.
class Calendario::AccountDataExportService
  include Calendario::AccountDataTransferSpec

  pattr_initialize [:export!]

  def perform
    export.update!(status: :processing)
    account = export.account

    Dir.mktmpdir do |dir|
      data = build_data(account)
      attachments_dir = File.join(dir, 'attachments')
      FileUtils.mkdir_p(attachments_dir)
      write_attachment_files(data['attachments'], attachments_dir)

      manifest = build_manifest(account, data)
      File.write(File.join(dir, 'data.json'), data.to_json)
      File.write(File.join(dir, 'manifest.json'), manifest.to_json)

      zip_path = File.join(dir, 'export.zip')
      build_zip(zip_path, dir, %w[data.json manifest.json attachments])

      export.export_file.attach(
        io: File.open(zip_path),
        filename: "export_cuenta_#{account.id}_#{Time.current.strftime('%Y%m%d%H%M%S')}.zip",
        content_type: 'application/zip'
      )
      export.update!(status: :completed, manifest: manifest)
    end
  rescue StandardError => e
    export.update!(status: :failed, error_message: "#{e.class}: #{e.message}")
    raise
  end

  private

  def build_data(account)
    MODELS.each_with_object({}) do |model_spec, data|
      relation = model_spec[:scope].call(account)
      data[model_spec[:key]] = relation.find_each.map { |record| record.attributes.except(*model_spec[:exclude]) }
    end
  end

  # Los bytes reales se guardan como "<attachment_id>-<nombre original>" --
  # el import los relaciona por el id del Attachment (ya viene en data.json
  # como "id" de esa fila, antes de remapear).
  def write_attachment_files(attachment_rows, attachments_dir)
    attachment_rows.each do |row|
      attachment = Attachment.find_by(id: row['id'])
      next unless attachment&.file&.attached?

      dest = File.join(attachments_dir, "#{row['id']}-#{attachment.file.filename}")
      attachment.file.blob.open { |tempfile| FileUtils.cp(tempfile.path, dest) }
    rescue StandardError => e
      Rails.logger.error("[Calendario::AccountDataExportService] no se pudo empaquetar attachment id=#{row['id']}: #{e.message}")
    end
  end

  def build_manifest(account, data)
    {
      format_version: FORMAT_VERSION,
      exported_at: Time.current.iso8601,
      account_id: account.id,
      account_name: account.name,
      counts: data.transform_values(&:size)
    }
  end

  def build_zip(zip_path, dir, entries)
    require 'zip'
    Zip::File.open(zip_path, create: true) do |zipfile|
      entries.each do |entry|
        path = File.join(dir, entry)
        if File.directory?(path)
          Dir.glob(File.join(path, '**', '*')).each do |file|
            next if File.directory?(file)

            zipfile.add(File.join(entry, File.basename(file)), file)
          end
        else
          zipfile.add(entry, path)
        end
      end
    end
  end
end
