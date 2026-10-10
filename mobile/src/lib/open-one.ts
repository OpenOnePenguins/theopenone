export type Pairing = { endpoint: string; token: string };
function isPrivateIPv4(host: string): boolean {
  if (!/^\d+\.\d+\.\d+\.\d+$/.test(host)) return false;
  const parts = host.split('.').map(Number);
  if (parts.some(part => part > 255)) return false;
  return parts[0] === 10 || (parts[0] === 172 && parts[1] >= 16 && parts[1] <= 31) ||
    (parts[0] === 192 && parts[1] === 168);
}
export function parsePairing(input: string): Pairing {
  try {
    if (input.length > 8000) throw new Error();
    const value = input.trim();
    const saved = value.startsWith('{') ? JSON.parse(value) : null;
    let url = new URL(saved ? saved.endpoint : value);
    const token = saved ? saved.token : url.hash.slice(1);
    if (!saved && url.protocol === 'open-one:') {
      // The installed app opens at its root route; credentials stay in the fragment.
      if (url.host || url.username || url.password || url.pathname !== '/' ||
          [...url.searchParams.keys()].join(',') !== 'endpoint') throw new Error();
      url = new URL(url.searchParams.get('endpoint')!);
      if (url.protocol !== 'https:' || url.hash) throw new Error();
    }
    if (!['http:', 'https:'].includes(url.protocol) ||
        !(['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) || isPrivateIPv4(url.hostname)))
      throw new Error('Use the LAN connection link from Open One. Both devices must be on the same Wi-Fi.');
    if (url.username || url.password || url.search || !['', '/'].includes(url.pathname) || typeof token !== 'string' || !/^[A-Za-z0-9_-]{32,256}$/.test(token)) throw new Error();
    return { endpoint: url.origin, token };
  } catch (e) {
    if (e instanceof Error && e.message.startsWith('Use the LAN')) throw e;
    throw new Error('Paste the connection link from Open One → Remote access.');
  }
}
export type Message = { id: string; role: string; text: string };
export type Conversation = {
  id: string; conversationKey: string; folder: string; title: string; provider: string;
  state: string; canReceive: boolean; readOnlyReason: string; requestID: string | null;
  choices: string[]; messages: Message[]; name: string;
};
export type Receipt = { status: 'queued' | 'staged' | 'submitting' | 'delivered' | 'rejected' | 'uncertain' | 'unknown'; message: string };
export type Operation = { id: string; text: string; at: number; conversationKey: string };
export function operationID(randomBytes: Uint8Array): string {
  if (randomBytes.length !== 16) throw new Error('Could not create a message ID.');
  const bytes = randomBytes.slice(); bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
  const hex = [...bytes].map(byte => byte.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
}
export function createOperation(id: string, text: string, conversationKey: string): Operation {
  return {id,text,conversationKey,at:Date.now()};
}
export class ApiError extends Error { constructor(message: string, readonly status: number) {super(message);} }
export class OpenOneClient {
  source: 'desktop' | 'sample' = 'desktop';
  private controllers = new Set<AbortController>();
  private closed = false;
  constructor(readonly pairing: Pairing, private fetcher: typeof fetch = fetch, private timeout = 12000) {}
  async request<T>(path: string, body?: unknown): Promise<T> {
    if(this.closed) throw new Error('Reconnect to your Mac first.');
    const controller = new AbortController(); this.controllers.add(controller);
    const timer = setTimeout(() => controller.abort(),this.timeout);
    try {
      const fetcher = this.fetcher;
      const response = await fetcher(`${this.pairing.endpoint}${path}`, {
        method: body === undefined ? 'GET' : 'POST', redirect: 'error', cache: 'no-store', signal: controller.signal,
        headers: {Authorization: `Bearer ${this.pairing.token}`, ...(body === undefined ? {} : {'Content-Type':'application/json'})},
        body: body === undefined ? undefined : JSON.stringify(body),
      });
      const value = await response.json();
      if(!response.ok) throw new ApiError(value.error || 'Open One rejected this request.',response.status);
      return value as T;
    } catch(e) {
      if(e instanceof ApiError) throw e;
      throw new Error('Could not reach Open One on your Mac. Keep it awake and Remote access enabled.');
    } finally {clearTimeout(timer);this.controllers.delete(controller);}
  }
  async connect() {
    const info = await this.request<{app:string;protocolVersion:number}>('/api/info');
    if(info.app !== 'open-one' || info.protocolVersion !== 2) throw new Error('Update Open One on your Mac to use this mobile app.');
  }
  async conversations(): Promise<Conversation[]> {
    const state = await this.request<{agents:Conversation[];source?:string}>('/api/state');
    if(!Array.isArray(state.agents)) throw new Error('Open One returned an invalid conversation list.');
    this.source = state.source === 'sample' ? 'sample' : 'desktop';
    return state.agents;
  }
  receipt(id: string): Promise<Receipt> {return this.request(`/api/receipts/${encodeURIComponent(id)}`);}
  async conversation(id: string): Promise<Conversation | undefined> {
    try { return await this.request<Conversation>(`/api/conversations/${encodeURIComponent(id)}`); }
    catch(e) {
      // Keep existing version-2 desktops compatible while they are updated.
      if(e instanceof ApiError && e.status===404) return (await this.conversations()).find(c=>c.id===id);
      throw e;
    }
  }
  close() {this.closed=true;this.controllers.forEach(c=>c.abort());this.controllers.clear();}
}
export async function getConversation(client: OpenOneClient, selected: Conversation) {
  const current = await client.conversation(selected.id);
  if(!current || current.id!==selected.id || current.conversationKey!==selected.conversationKey) throw new Error('This conversation changed. Return to conversations and open it again.');
  return current;
}
// Receipt checks are small and sequential. Slow networks never accumulate
// overlapping requests, and a receipt never replays the original command.
export function watchReceipt(client: Pick<OpenOneClient, 'receipt'>, id: string,
  onReceipt: (receipt: Receipt) => Promise<void>, onError: (error: unknown) => void, intervalMs = 250) {
  let stopped = false; let timer: ReturnType<typeof setTimeout> | undefined;
  const poll = async () => {
    try {
      const receipt = await client.receipt(id);
      if(stopped) return;
      await onReceipt(receipt);
      if(receipt.status==='delivered' || receipt.status==='rejected') return;
    } catch(e) {if(!stopped) onError(e);}
    if(!stopped) timer=setTimeout(()=>void poll(),intervalMs);
  };
  void poll();
  return () => {stopped=true;clearTimeout(timer);};
}
export async function sendMessage(client: OpenOneClient, conversation: Conversation, operation: Operation,
  persist: () => Promise<void>, clearRejected: () => Promise<void>, choiceIndex?: number) {
  if(!operation.text.trim() || operation.text.length>32000) throw new Error('Enter a message of at most 32,000 characters.');
  // The POST validates current recipient/question atomically on the Mac. A
  // preflight GET adds a round trip and cannot prevent a change after that GET.
  const current = conversation;
  if(operation.conversationKey!==current.conversationKey) throw new Error('This conversation changed. Reopen it before replying.');
  if(!current.canReceive) throw new Error(current.readOnlyReason || 'This conversation cannot receive a message right now.');
  if(choiceIndex!==undefined && (!Number.isInteger(choiceIndex) || current.choices[choiceIndex]!==operation.text)) throw new Error('That choice is no longer available.');
  await persist(); // Before any side effect, including an HTTP response lost in flight.
  try {
    const response = await client.request<{id:string}>('/api/commands',{
      operationID:operation.id, agentID:current.id, conversationKey:current.conversationKey,
      requestID:current.requestID, text:operation.text, choiceIndex:choiceIndex ?? null,
    });
    if(response.id!==operation.id) throw new Error('Could not verify the message receipt. Check your Mac.');
  } catch(e) {
    // These responses prove that this command was not accepted. Never auto-retry a timeout or server error.
    if(e instanceof ApiError && [400,401,403,409,413,415,429].includes(e.status)) await clearRejected();
    throw e;
  }
}
