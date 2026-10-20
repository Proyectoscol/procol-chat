class CreateAuditoriaCategoryMentions < ActiveRecord::Migration[7.2]
  def change
    create_table :auditoria_category_mentions do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :category, null: false, foreign_key: { to_table: :auditoria_categories, on_delete: :cascade }
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }
      # nil para menciones de IA (el LLM reporta el dia, no un mensaje puntual
      # -- ver Auditoria::ConversationAnalyzerService#sync_ai_categories!).
      # Para palabra clave, siempre presente: una fila por cada mensaje que
      # matchea (ver Auditoria::KeywordCategoryMatcherService).
      t.references :message, null: true, foreign_key: { on_delete: :cascade }
      # date, no datetime: la granularidad que de verdad importa para la
      # grafica de menciones-por-dia es el dia calendario, no la hora exacta
      # -- igual de IA (que solo reporta dia) que de palabra clave (que si
      # tiene timestamp exacto via message, pero se trunca a dia aqui para
      # que ambos mecanismos alimenten el mismo GROUP BY sin caso especial).
      t.date :occurred_on, null: false

      t.datetime :created_at, null: false
    end

    # Palabra clave: un mensaje no puede disparar dos veces la misma
    # categoria.
    add_index :auditoria_category_mentions, [:message_id, :category_id],
              unique: true, where: 'message_id IS NOT NULL', name: 'index_auditoria_mentions_on_message_and_category'
    # IA: un mismo dia de una misma conversacion no puede quedar duplicado
    # para la misma categoria.
    add_index :auditoria_category_mentions, [:conversation_id, :category_id, :occurred_on],
              unique: true, where: 'message_id IS NULL', name: 'index_auditoria_mentions_on_conv_category_day'
    add_index :auditoria_category_mentions, [:account_id, :category_id, :occurred_on],
              name: 'index_auditoria_mentions_on_account_category_day'
  end
end
