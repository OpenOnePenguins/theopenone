import React, { createContext, useContext, useEffect, useRef, useState } from 'react';
import { AppState, Platform } from 'react-native';
import * as Linking from 'expo-linking';
import { Conversation, OpenOneClient, Pairing, parsePairing } from './open-one';
import { credentials } from './storage';

type Store = {
  client: OpenOneClient | null; pairing: Pairing | null; state: string; error: string; conversations: Conversation[];
  selected: Conversation | null; select: (c: Conversation) => void; connect: (p: Pairing) => Promise<void>;
  disconnect: () => Promise<void>; refresh: () => Promise<void>; ready: boolean;
};
const Context = createContext<Store>(null!);
export function Provider({ children }: { children: React.ReactNode }) {
  const [client, setClient] = useState<OpenOneClient | null>(null);
  const ref = useRef<OpenOneClient | null>(null);
  const pairingRef = useRef<Pairing | null>(null);
  const generation = useRef(0);
  const [pairing, setPairing] = useState<Pairing | null>(null);
  const [state, setState] = useState('offline');
  const [error, setError] = useState('');
  const [ready, setReady] = useState(false);
  const [conversations, setConversations] = useState<Conversation[]>([]);
  const [selected, select] = useState<Conversation | null>(null);
  async function connect(p: Pairing) {
    const gen = ++generation.current;
    ref.current?.close();
    const next = new OpenOneClient(p); ref.current = next;
    pairingRef.current = p; setPairing(p);
    setClient(null); setConversations([]); select(null); setState('connecting'); setError('');
    try {
      await next.connect();
      const items = await next.conversations();
      if (generation.current !== gen) { next.close(); return; }
      await credentials.set(JSON.stringify(p));
      if (generation.current !== gen) { next.close(); return; }
      pairingRef.current = p; setPairing(p); setClient(next); setConversations(items); setState('connected');
    } catch (e) {
      next.close();
      if (generation.current !== gen) return;
      setState('offline'); setError(e instanceof Error ? e.message : 'Connection failed.');
      throw e;
    }
  }
  async function disconnect() {
    ++generation.current; pairingRef.current = null; ref.current?.close(); ref.current = null;
    setClient(null); setPairing(null); setState('offline'); setError(''); setConversations([]); select(null);
    await credentials.remove();
  }
  async function refresh() {
    const active = ref.current; const gen = generation.current;
    if (!active) return;
    try { const items = await active.conversations(); if (generation.current === gen) {setConversations(items);setError('');setState('connected');} }
    catch (e) { if (generation.current === gen) {setError(e instanceof Error ? e.message : 'Could not refresh.');setState('offline');} }
  }
  useEffect(() => {
    let mounted = true;
    const restore = async () => {
      const gen = generation.current;
      try {
        const initial = Platform.OS === 'web' ? null : await Linking.getInitialURL();
        const value = initial?.startsWith('open-one:') ? initial : await credentials.get();
        // An incoming link or a disconnect takes precedence over a slow restore.
        if (mounted && value && generation.current === gen) await connect(parsePairing(value));
      } catch (e) { if (mounted && generation.current === gen) setError(e instanceof Error ? e.message : 'Could not reconnect.'); }
      finally { if (mounted) setReady(true); }
    };
    void restore();
    const incomingLink = () => { if (/^#[A-Za-z0-9_-]{32,256}$/.test(window.location.hash)) void restore(); };
    if (Platform.OS === 'web') window.addEventListener('hashchange', incomingLink);
    const linkSubscription = Platform.OS === 'web' ? null : Linking.addEventListener('url', ({url}) => {
      if (!mounted || !url.startsWith('open-one:')) return;
      try { void connect(parsePairing(url)).catch(() => {}); }
      catch (e) { setError(e instanceof Error ? e.message : 'Invalid connection link.'); }
    });
    const subscription = AppState.addEventListener('change', state => {
      if (state !== 'active') { ++generation.current; ref.current?.close(); setClient(null); setState('offline'); }
      else if (pairingRef.current) void connect(pairingRef.current).catch(() => {});
    });
    // The generation is a connection counter, not a DOM ref.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    return () => { mounted = false; ++generation.current; ref.current?.close(); subscription.remove(); linkSubscription?.remove(); if (Platform.OS === 'web') window.removeEventListener('hashchange', incomingLink); };
  }, []);
  return <Context.Provider value={{ client, pairing, state, error, conversations, selected, select, connect, disconnect, refresh, ready }}>{children}</Context.Provider>;
}
export const useStore = () => useContext(Context);
