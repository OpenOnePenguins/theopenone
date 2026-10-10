import { useEffect, useRef, useState } from 'react';
import { KeyboardAvoidingView, Platform, Pressable, ScrollView, Text, TextInput, View } from 'react-native';
import { getRandomBytes } from 'expo-crypto';
import { router, useLocalSearchParams } from 'expo-router';
import { Button, colors, Notice, Shell, s } from '../components/ui';
import { ProviderLogo } from '../components/ProviderLogo';
import { Conversation, createOperation, getConversation, operationID, Operation, Receipt, sendMessage, watchReceipt } from '../lib/open-one';
import { useStore } from '../lib/store';
import { drafts } from '../lib/storage';

export default function Chat() {
 const store = useStore();
 const { id, conversationKey } = useLocalSearchParams<{id?: string; conversationKey?: string}>();
 const selected = id && conversationKey
  ? store.conversations.find(c => c.id === id && c.conversationKey === conversationKey)
  : store.selected;
 if (!store.ready || store.state === 'connecting') return <Shell><Text style={s.subtitle}>Reconnecting to your Mac…</Text></Shell>;
 if (!selected || !store.pairing) return <Shell><View style={{marginTop:40,gap:16}}>
  <Notice text={store.error || 'Open this conversation from the list to continue.'}/>
  <Button title="Back to conversations" onPress={()=>router.replace('/conversations')}/>
 </View></Shell>;
 return <ChatConversation key={`${store.pairing.endpoint}:${selected.conversationKey}`} selected={selected}/>;
}

function ChatConversation({selected}: {selected: Conversation}) {
 const store = useStore();
 const [conversation, setConversation] = useState<Conversation | null>(selected);
 const [draft, setDraft] = useState(''); const [loaded, setLoaded] = useState(false);
 const [pending, setPending] = useState<Operation | null>(null);
 const [receipt, setReceipt] = useState<Receipt | null>(null);
 const [expiredID, setExpiredID] = useState<string | null>(null);
 const [sending, setSending] = useState(false); const [error, setError] = useState('');
 const [readError, setReadError] = useState('');
 const scroll = useRef<ScrollView>(null); const lock = useRef(false);
 const confirmedOperation = useRef<string | null>(null);
 const nearBottom = useRef(true); const writes = useRef(Promise.resolve());
 const key = `open-one:${store.pairing?.endpoint}:${selected?.conversationKey}`;
 const pendingKey = `${key}:pending`;
 const deliveryConfirmed = receipt?.status==='delivered';
 const saveDraft = (text: string) => {
  setDraft(text);
  writes.current = writes.current.then(() => drafts.setItem(key,text));
  writes.current.catch(() => setError('Could not save your draft on this device.'));
 };
 useEffect(() => {
  let active = true;
  Promise.all([drafts.getItem(key),drafts.getItem(pendingKey)]).then(([text,operation]) => {
   if(active) {setDraft(text || '');setPending(operation ? JSON.parse(operation) : null);setLoaded(true);}
  }).catch(() => setError('Could not read the saved draft.'));
  return () => {active=false;};
 },[key,pendingKey]);
 useEffect(() => {
  if(!pending) return;
  const timer=setTimeout(()=>setExpiredID(pending.id),Math.max(0,35000-(Date.now()-pending.at)));
  return ()=>clearTimeout(timer);
 },[pending]);
 useEffect(() => {
  let active=true;let busy=false;
  const refresh=async()=>{
   if(busy || !store.client || !selected) return;busy=true;
   try {
    const current=await getConversation(store.client,selected);
    if(active){setConversation(current);setReadError('');}
   } catch(e){if(active)setReadError(e instanceof Error ? e.message : 'Could not refresh this conversation.');}
   finally{busy=false;}
  };
  void refresh();const timer=setInterval(()=>void refresh(),2000);
  return ()=>{active=false;clearInterval(timer);};
 },[store.client,selected,deliveryConfirmed]);
 useEffect(() => {
  if(!pending || !store.client) return;
  let active=true;
  const client=store.client;
  const stop=watchReceipt(client,pending.id,async result=>{
   // The marker is saved just before POST; an early missing receipt is normal.
   if(result.status==='unknown' && Date.now()-pending.at<35000) return;
   if(!active) return;
   setReceipt(result);
   if(result.status==='delivered'){
    confirmedOperation.current=pending.id;
    // Receipt confirmation does not wait for a history download. Keep the
    // durable marker until removing the delivered draft succeeds.
    await writes.current;await drafts.setItem(key,'');await drafts.removeItem(pendingKey);
    if(!active) return;
    setDraft('');setPending(null);setError('');nearBottom.current=true;
   }else if(result.status==='rejected'){
    await drafts.removeItem(pendingKey);
    if(active){setPending(null);setError(result.message);}
   }
  },e=>{if(active)setReadError(e instanceof Error ? e.message : 'Could not check delivery.');},expiredID===pending.id?2000:250);
  return ()=>{active=false;stop();};
 },[store.client,selected,pending,key,pendingKey,expiredID]);
 async function send(text: string, choiceIndex?: number) {
  if(lock.current || !conversation || !store.client || pending) return;
  lock.current=true;setSending(true);setError('');setReceipt(null);
  let operation: Operation | undefined;
  try{
   // getRandomValues works on LAN HTTP; browser randomUUID requires a secure origin.
   operation=createOperation(operationID(getRandomBytes(16)),text,conversation.conversationKey);
   const outgoing=operation;
   await writes.current;
   await sendMessage(store.client,conversation,operation,async()=>{
    await drafts.setItem(key,text);setDraft(text);
    await drafts.setItem(pendingKey,JSON.stringify(outgoing));
    setReceipt({status:'queued',message:'Sending to Open One on your Mac.'});setPending(outgoing);nearBottom.current=true;
   },async()=>{await drafts.removeItem(pendingKey);setPending(null);setReceipt(null);},choiceIndex);
   // A fast receipt can arrive before the POST response. Never replace an
   // accepted receipt with a late "queued" state or lost-response error.
  }catch(e){if(!operation || confirmedOperation.current!==operation.id)setError(e instanceof Error ? e.message : 'Could not send.');}
  finally{lock.current=false;setSending(false);}
 }
 if(!conversation) return <Shell><View style={{marginTop:40}}><Button title="Back to conversations" onPress={()=>router.replace('/conversations')}/></View></Shell>;
 const unresolved = pending && (['unknown','uncertain'].includes(receipt?.status || '') || expiredID===pending.id);
 const unavailable = !conversation.canReceive || !!readError || store.state!=='connected';
 return <Shell>
 <View style={[s.row,{paddingVertical:14,borderBottomWidth:1,borderBottomColor:colors.line,gap:10}]}><Pressable accessibilityRole="button" accessibilityLabel="Back to conversations" onPress={()=>router.replace('/conversations')} style={({pressed})=>({width:44,height:44,alignItems:'center',justifyContent:'center',borderWidth:1,borderColor:colors.line,borderRadius:9,backgroundColor:pressed?colors.wash:colors.surface})}><Text style={{fontSize:28,lineHeight:30,color:colors.ink}}>‹</Text></Pressable><ProviderLogo provider={conversation.provider} size={24}/><View style={{flex:1}}><Text numberOfLines={2} style={{fontWeight:'600',fontSize:15,lineHeight:20,letterSpacing:-.2,color:colors.ink}}>{conversation.title || conversation.name}</Text><Text numberOfLines={1} style={[s.label,{marginTop:4,fontSize:11}]}>{conversation.provider} · {conversation.folder || conversation.state}</Text></View></View>
 <KeyboardAvoidingView style={{flex:1}} behavior={Platform.OS==='ios'?'padding':undefined}>
 <ScrollView ref={scroll} contentContainerStyle={{paddingVertical:20,gap:16}} scrollEventThrottle={100} onScroll={e=>{const {layoutMeasurement,contentOffset,contentSize}=e.nativeEvent;nearBottom.current=contentSize.height-contentOffset.y-layoutMeasurement.height<120;}} onContentSizeChange={()=>{if(nearBottom.current)scroll.current?.scrollToEnd({animated:false});}}>
 <Text style={[s.label,{textAlign:'center'}]}>RECENT CONVERSATION</Text>
 {conversation.messages.map(m=><View key={m.id} style={[s.message,m.role==='user' && s.userMessage]}><View style={[s.row,{gap:7,marginBottom:10}]}>{m.role==='assistant' && <ProviderLogo provider={conversation.provider} size={15}/>}<Text style={{fontSize:11,fontWeight:'600',color:m.role==='user'?colors.blue:colors.muted}}>{m.role==='user'?'You':m.role==='assistant'?conversation.provider:m.role}</Text></View><Text selectable style={{fontSize:15,lineHeight:24,color:colors.ink}}>{m.text}</Text></View>)}
 {conversation.messages.length===0 && <Text style={s.subtitle}>No messages yet.</Text>}
 </ScrollView>
 <Notice text={error || readError || (!conversation.canReceive ? conversation.readOnlyReason : '')}/>
 {receipt && <Text accessibilityLiveRegion="polite" style={{color:colors.green,fontSize:13,paddingVertical:8}}>{receipt.message}</Text>}
 {unresolved && !sending && <View style={{paddingBottom:12}}><Notice text="Delivery is not confirmed. Check this conversation on your Mac before sending again."/><Button secondary title="I checked my Mac — unlock sending" onPress={()=>void drafts.removeItem(pendingKey).then(()=>{setPending(null);setReceipt(null);setError('');})}/></View>}
 {(store.state!=='connected' || !!readError) && <Button secondary title="Reconnect to Mac" disabled={store.state==='connecting'} onPress={()=>store.pairing && void store.connect(store.pairing).catch(()=>{})}/>}
 <View style={{paddingTop:12,paddingBottom:18,gap:10,borderTopWidth:1,borderTopColor:colors.line}}>
 {conversation.requestID && conversation.choices.length>0 && <View style={{gap:8}}>{conversation.choices.map((choice,i)=><Button key={i} secondary title={choice} disabled={!loaded||unavailable||sending||!!pending} onPress={()=>void send(choice,i)}/>)}</View>}
 <TextInput accessibilityLabel="Message" placeholder="Continue the conversation…" placeholderTextColor={colors.muted} selectionColor={colors.blue} multiline maxLength={32000} value={draft} editable={loaded&&!sending&&!pending} onChangeText={saveDraft} style={[s.input,{minHeight:62,maxHeight:160}]}/>
 <Button title={sending?'Sending…':pending?'Waiting for your Mac…':'Send message  ↑'} disabled={!loaded||!draft.trim()||sending||!!pending||unavailable} onPress={()=>void send(draft)}/>
 <Text style={{fontSize:10,textAlign:'center',color:colors.muted}}>Local Wi-Fi · Same conversation and worktree</Text>
 </View></KeyboardAvoidingView></Shell>;
}
