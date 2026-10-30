export const closeCause = (selfClosed, usb) => (selfClosed ? 'self' : usb === false ? 'phoneNotOnUsb' : usb === true ? 'otherClient' : 'unknown');

export const CAUSE_TEXT = Object.freeze({
  self: 'connection closed by this tool',
  phoneNotOnUsb: 'the phone is not on USB (cable unplugged or the phone asleep): plug it in and unlock it',
  otherClient: 'the phone is on USB, so another inspector client probably took the tab',
  unknown: 'the proxy closed the connection and the USB bus could not be read',
});

export function closedMessage(selfClosed, code, usb) {
  const cause = closeCause(selfClosed, usb);
  return cause === 'self' ? CAUSE_TEXT.self : `connection closed by the proxy (code ${code}): ${CAUSE_TEXT[cause]}`;
}
