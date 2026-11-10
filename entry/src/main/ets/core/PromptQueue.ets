import { ChatAttachment, MessagePart, filePart, imagePart, textPart } from './Types';
import { isPastedAttachment, pastePlaceholder, pasteRelativePath } from './Paste';

/**
 * A prompt typed while the agent was still generating. OpenMinis keeps these
 * in a FIFO and injects them at the next tool boundary (or after the run
 * stops); the UI mirrors the same queue so an interrupted run can resend the
 * entries the runtime never consumed.
 */
export class QueuedPrompt {
  text: string;
  attachments: ChatAttachment[];
  /** Session that was active when the prompt was queued. */
  sessionId: string;

  constructor(text: string, attachments: ChatAttachment[], sessionId: string) {
    this.text = text;
    this.attachments = attachments;
    this.sessionId = sessionId;
  }
}

/** Multimodal parts for the queued attachments, in composer order. */
export function queuedParts(item: QueuedPrompt): MessagePart[] {
  const parts: MessagePart[] = [];
  for (let i = 0; i < item.attachments.length; i++) {
    const uri: string = item.attachments[i].uri;
    const mime: string = item.attachments[i].mimeType;
    if (isPastedAttachment(uri, mime)) {
      parts.push(textPart(pastePlaceholder(pasteRelativePath(uri))));
      parts.push(filePart(uri, mime));
    } else {
      parts.push(imagePart(uri, mime));
    }
  }
  return parts;
}

export function enqueueQueued(queue: QueuedPrompt[], item: QueuedPrompt): QueuedPrompt[] {
  const next: QueuedPrompt[] = queue.slice();
  next.push(item);
  return next;
}

/** Drop entries the runtime already injected into the transcript. */
export function dropQueued(queue: QueuedPrompt[], count: number): QueuedPrompt[] {
  if (count <= 0) {
    return queue;
  }
  return queue.slice(Math.min(count, queue.length));
}
