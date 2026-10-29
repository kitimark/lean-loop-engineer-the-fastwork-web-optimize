// TS twin of Lean `closeCause` (lean/Fw/Device/Feel.lean; golden kind closeCause in feel.jsonl): why the proxy connection
// closed, given whether this tool closed it and what the USB probe saw (true present, false absent, null unreadable).
export const closeCause = (selfClosed, usb) => (selfClosed ? 'self' : usb === false ? 'phoneNotOnUsb' : usb === true ? 'otherClient' : 'unknown');

export const CAUSE_TEXT = Object.freeze({
  self: 'connection closed by this tool',
  phoneNotOnUsb: 'the phone is not on USB (cable unplugged or the phone asleep): plug it in and unlock it',
  otherClient: 'the phone is on USB, so another inspector client probably took the tab',
  unknown: 'the proxy closed the connection and the USB bus could not be read',
});

/** The error text for a closed connection. The probe runs once, at the close. */
export function closedMessage(selfClosed, code, usb) {
  const cause = closeCause(selfClosed, usb);
  return cause === 'self' ? CAUSE_TEXT.self : `connection closed by the proxy (code ${code}): ${CAUSE_TEXT[cause]}`;
}
