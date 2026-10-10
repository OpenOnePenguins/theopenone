import { useState } from 'react';
import { Platform, ScrollView, Text, TextInput, View } from 'react-native';
import { Redirect, router } from 'expo-router';
import { Brand, Button, colors, Notice, Shell, s } from '../components/ui';
import { ProviderLogo } from '../components/ProviderLogo';
import { parsePairing } from '../lib/open-one';
import { useStore } from '../lib/store';
export default function Connect() {
 const store = useStore(); const [code, setCode] = useState(''); const [error, setError] = useState('');
 if (store.state === 'connected') return <Redirect href="/conversations" />;
 async function pair() { setError(''); try { await store.connect(parsePairing(code)); setCode(''); router.replace('/conversations'); } catch(e) { setError(e instanceof Error ? e.message : 'Could not connect.'); } }
 return <Shell><Brand /><ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={{paddingTop: 32, paddingBottom: 32}}>
  <Text style={s.eyebrow}>YOUR WORK, WITH YOU</Text><Text style={s.title}>Pick up where{ '\n' }you left off.</Text>
  <Text style={s.subtitle}>Continue your Open One conversations from your phone. Same context. Same worktree.</Text>
  <View style={[s.row,{gap:20,marginTop:22}]}>{['Codex','Claude','OpenCode','Pi'].map(provider=><View key={provider} style={{alignItems:'center',gap:7}}><ProviderLogo provider={provider} size={22}/><Text style={{fontSize:10,color:colors.muted}}>{provider}</Text></View>)}</View>
  <View style={{marginVertical:26,borderWidth:1,borderColor:colors.line,borderRadius:10,backgroundColor:colors.surface,paddingHorizontal:14}}>{['Put your phone and Mac on the same Wi-Fi. Open Open One → Remote access on the Mac.', 'Click Connect phone. Keep your Mac awake and Open One running.', Platform.OS === 'web' ? 'Scan the QR with iPhone Camera → Safari, or paste the full connection link below.' : 'Paste the full LAN connection link below.'].map((text,i) => <View style={[s.row,{paddingVertical:14,alignItems:'flex-start',...(i<2?{borderBottomWidth:1,borderBottomColor:colors.line}:{})}]} key={text}><Text style={[s.label,{color:colors.blue,marginTop:2}]}>0{i+1}</Text><Text style={{flex:1,fontSize:13,lineHeight:20,color:colors.ink}}>{text}</Text></View>)}</View>
  <Text style={[s.label,{marginBottom: 10}]}>CONNECTION LINK</Text><TextInput value={code} onChangeText={setCode} accessibilityLabel="Connection link" placeholder="Paste your Open One connection link" placeholderTextColor={colors.muted} selectionColor={colors.blue} style={s.input} secureTextEntry autoCapitalize="none" autoCorrect={false} />
  <Notice text={error || store.error}/><View style={{height: 14}}/><Button title={store.state === 'connecting' ? 'Connecting…' : 'Connect to my Mac  →'} disabled={!code.trim() || store.state === 'connecting' || !store.ready} onPress={() => void pair()} />
  {store.pairing && <View style={{marginTop: 12}}><Button secondary title="Reconnect saved Mac" disabled={store.state === 'connecting'} onPress={() => void store.connect(store.pairing!).catch(() => {})}/></View>}
  <Text style={[s.subtitle,{fontSize:11,lineHeight:18,textAlign:'center'}]}>Local Wi-Fi only. Keep your connection link private.{ '\n' }If it expires, scan a fresh QR from your Mac.</Text>
 </ScrollView></Shell>;
}
