// Reproduce un prompt de audio y recoge 1 dígito DTMF del caller.
const DIGIT_TIMEOUT_MS = Number(process.env.IVR_DIGIT_TIMEOUT || 10) * 1000;

export async function playPromptAndGetDigit(
  _client,
  channel,
  prompt = process.env.IVR_PROMPT || 'ivr-ciudades',
) {
  return new Promise((resolve) => {
    let playback = null;
    let settled = false;
    let hungUp = false;

    const settle = (digit) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      channel.removeListener('ChannelDtmfReceived', onDigit);
      channel.removeListener('ChannelHangupRequest', onHangup);
      channel.removeListener('StasisEnd', onHangup);
      playback?.stop().catch(() => {});
      resolve({ digit, hungUp });
    };

    const onDigit = (evt) => {
      if (hungUp) return;
      settle(evt.digit);
    };
    const onHangup = () => {
      hungUp = true;
      settle(null);
    };
    const timer = setTimeout(() => settle(null), DIGIT_TIMEOUT_MS);

    channel.on('ChannelDtmfReceived', onDigit);
    channel.once('ChannelHangupRequest', onHangup);
    channel.once('StasisEnd', onHangup);

    channel
      .play({ media: `sound:${prompt}` })
      .then((pb) => { playback = pb; })
      .catch(() => settle(null));
  });
}
