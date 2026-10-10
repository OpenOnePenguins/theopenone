import { useEffect, useState } from 'react';
import { FlatList, Pressable, Text, TextInput, View } from 'react-native';
import { router } from 'expo-router';
import { AgentStatus, Brand, Button, colors, Notice, Shell, s } from '../components/ui';
import { ProviderLogo } from '../components/ProviderLogo';
import { useStore } from '../lib/store';
export default function Conversations() {
 const store = useStore(); const [query, setQuery] = useState(''); const [refreshing, setRefreshing] = useState(false);
 useEffect(() => { const timer = setInterval(() => { if (store.client) void store.refresh(); },10000); return () => clearInterval(timer); }, [store.client]); // eslint-disable-line react-hooks/exhaustive-deps
 async function refresh() { setRefreshing(true); await store.refresh(); setRefreshing(false); }
 const visible = store.conversations.filter(c => `${c.title} ${c.folder} ${c.provider} ${c.name}`.toLowerCase().includes(query.toLowerCase()));
 return <Shell><Brand/><View style={[s.row,{marginTop: 22,marginBottom: 18}]}><View style={{flex: 1}}><Text style={[s.title,{fontSize: 27,lineHeight: 33,letterSpacing: -.7}]}>Conversations</Text><Text style={{color:colors.muted,fontSize:12,marginTop:5}}>Same agents. Same worktrees.</Text></View><View style={[s.row,{gap:5}]}><View style={{width:6,height:6,borderRadius:3,backgroundColor:store.state==='connected'?colors.green:colors.muted}}/><Text style={{color:colors.muted,fontSize:11}}>{store.state === 'connected' ? 'Mac online' : store.state}</Text></View></View>
 <TextInput accessibilityLabel="Search conversations" value={query} onChangeText={setQuery} placeholder="Search conversations, agents, worktrees" placeholderTextColor={colors.muted} selectionColor={colors.blue} style={[s.input,{marginBottom: 12,fontSize:14}]} />
 <Notice text={store.client?.source === 'sample' ? 'Sample connection: these are test conversations. Disconnect and scan the QR from Open One on your Mac for your real work.' : store.error}/>
 <View style={[s.row,{justifyContent:'space-between',marginBottom:12}]}><Text style={s.label}>{query ? `${visible.length} of ${store.conversations.length}` : store.conversations.length} conversations</Text><Text style={[s.label,{fontSize:10}]}>FROM YOUR MAC</Text></View>
 {store.state !== 'connected' && <Button title="Reconnect to Mac" disabled={store.state === 'connecting'} onPress={() => store.pairing ? void store.connect(store.pairing).catch(() => {}) : router.replace('/')} />}
 <FlatList data={visible} keyExtractor={c => c.id} refreshing={refreshing} onRefresh={() => void refresh()} contentContainerStyle={{paddingBottom: 14}} ListEmptyComponent={<Text style={s.subtitle}>{query ? 'No matching conversations.' : 'Track a conversation in Open One on your Mac, then pull to refresh.'}</Text>} renderItem={({item}) => <Pressable accessibilityRole="button" accessibilityLabel={`${item.provider}: ${item.title || item.name}, ${item.folder}, ${item.state}`} onPress={() => {store.select(item); router.push({pathname:'/chat',params:{id:item.id,conversationKey:item.conversationKey}});}} style={({pressed}) => [s.card, {backgroundColor:pressed?colors.wash:colors.surface}]}>
 <View style={[s.row,{gap:9}]}><ProviderLogo provider={item.provider} size={19} framed/><Text style={{flex:1,color:colors.ink,fontSize:12,fontWeight:'500'}}>{item.provider}</Text><AgentStatus state={item.state}/><Text style={{color:colors.muted,fontSize:18,marginLeft:2}}>›</Text></View>
 <Text numberOfLines={2} style={{fontSize:16,lineHeight:22,fontWeight:'600',letterSpacing:-.3,color:colors.ink,marginTop:12}}>{item.title || item.name}</Text>
 <Text numberOfLines={1} style={{fontSize:11,color:colors.muted,marginTop:5,fontFamily:'monospace'}}>{item.folder || 'Local conversation'}</Text>
 <Text numberOfLines={2} style={{fontSize:13,lineHeight:19,color:colors.muted,marginTop:10}}>{item.messages.at(-1)?.text || 'Open conversation'}</Text>
 </Pressable>}/><View style={{paddingVertical:12,borderTopWidth:1,borderTopColor:colors.line}}><Button secondary compact title="Disconnect this Mac" onPress={() => void store.disconnect().then(() => router.replace('/'))}/></View></Shell>;
}
