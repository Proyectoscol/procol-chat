# Error tecnico (zip corrupto, sin _chat.txt, etc.) -- a diferencia de
# Import::WhatsappChatNeedsReviewError esto no es algo que una persona
# pueda resolver editando los datos del batch, asi que el job lo deja
# marcado como :failed en vez de :needs_review.
class Import::WhatsappChatParseError < StandardError; end
