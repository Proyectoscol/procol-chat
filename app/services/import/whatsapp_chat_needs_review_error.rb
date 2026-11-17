# Se levanta cuando el import no puede seguir de forma segura sin que una
# persona lo revise -- ej. el remitente configurado como "nosotros" no
# aparece en el chat, hay mas de 2 remitentes distintos, o el numero de
# telefono dado no es valido. Nunca se adivina en estos casos: el batch
# queda en :needs_review y no se crea ningun mensaje.
class Import::WhatsappChatNeedsReviewError < StandardError; end
