import React from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { BrandLogo } from './BrandLogo';

// Match the desktop Inbox's charcoal panels, blue selection, and state accents.
export const colors = {
 bg: '#161616', ink: '#F2F2F7', muted: '#AAAAB1', line: '#323235',
 green: '#40D97A', wash: '#252527', surface: '#1E1E20',
 blue: '#84B9FF', userBubble: '#21364F', warning: '#FFCC66', warningWash: '#332B1F',
};
export function Shell({ children }: { children: React.ReactNode }) { return <SafeAreaView style={s.safe}><View style={s.shell}>{children}</View></SafeAreaView>; }
export function Brand() { return <View style={s.brand}><BrandLogo size={28} /><Text style={s.wordmark}>Open One</Text><View style={s.localBadge}><Text style={s.beta}>LOCAL WI-FI</Text></View></View>; }
export function Button({ title, onPress, disabled = false, secondary = false, compact = false }: { title: string; onPress: () => void; disabled?: boolean; secondary?: boolean; compact?: boolean }) {
  return <Pressable accessibilityRole="button" accessibilityLabel={title} accessibilityState={{disabled}} onPress={onPress} disabled={disabled} style={({pressed}) => [s.button, compact && {minHeight: 44, paddingHorizontal: 12}, secondary && s.secondary, disabled && s.disabled, pressed && { opacity: .75 }]}><Text style={[s.buttonText, secondary && {color: colors.ink}, disabled && {color: colors.muted}]}>{title}</Text></Pressable>;
}
export function AgentStatus({ state }: { state: string }) {
  const color = state === 'working' ? colors.green : state === 'waiting' ? colors.warning : colors.muted;
  return <View style={[s.status,{borderColor: state === 'working' ? '#304A38' : state === 'waiting' ? '#594A30' : colors.line}]}><View style={{width:5,height:5,borderRadius:3,backgroundColor:color}}/><Text style={{fontSize:11,fontWeight:'500',color}}>{state === 'working' ? 'Working' : state === 'waiting' ? 'Needs reply' : state.charAt(0).toUpperCase()+state.slice(1)}</Text></View>;
}
export function Notice({ text }: { text?: string }) { return text ? <View accessibilityRole="alert" style={s.notice}><Text style={{color: colors.warning, lineHeight: 21}}>{text}</Text></View> : null; }
export const s = StyleSheet.create({
 safe: { flex: 1, backgroundColor: colors.bg }, shell: { flex: 1, width: '100%', maxWidth: 640, alignSelf: 'center', paddingHorizontal: 20 },
 brand: { flexDirection: 'row', alignItems: 'center', paddingVertical: 16, gap: 9, borderBottomWidth: 1, borderBottomColor: colors.line },
 wordmark: { color: colors.ink, fontSize: 18, fontWeight: '600', letterSpacing: -.4 }, beta: { fontSize: 9, fontWeight:'600', letterSpacing: .8, color: colors.muted },
 localBadge: {marginLeft:'auto',paddingHorizontal:8,paddingVertical:5,borderRadius:5,borderWidth:1,borderColor:colors.line},
 status: {flexDirection:'row',alignItems:'center',gap:5,paddingHorizontal:7,paddingVertical:4,borderRadius:5,borderWidth:1},
 eyebrow: { color: colors.muted, fontSize: 10, fontWeight: '600', letterSpacing: 1.1, marginBottom: 8 }, title: { color: colors.ink, fontSize: 34, lineHeight: 39, letterSpacing: -1, fontWeight: '600' }, subtitle: { color: colors.muted, fontSize: 14, lineHeight: 22, marginTop: 12 },
 button: { backgroundColor: colors.ink, minHeight: 48, borderRadius: 9, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 16, borderWidth: 1, borderColor: colors.ink },
 buttonText: { color: colors.bg, fontSize: 15, fontWeight: '600' }, secondary: { backgroundColor: colors.wash, borderColor: colors.line }, disabled: { backgroundColor: colors.wash, borderColor: colors.line },
 notice: { backgroundColor: colors.warningWash, borderWidth: 1, borderColor: '#594A30', padding: 14, borderRadius: 10, marginVertical: 12 },
 input: { borderWidth: 1, borderColor: colors.line, backgroundColor: colors.surface, borderRadius: 9, padding: 13, fontSize: 15, color: colors.ink },
 label: { color: colors.muted, fontSize: 11, fontWeight: '500', letterSpacing: .5 }, row: { flexDirection: 'row', alignItems: 'center', gap: 12 },
 card: { padding: 14, marginBottom: 9, borderWidth: 1, borderColor: colors.line, backgroundColor: colors.surface, borderRadius: 10 },
 message: { backgroundColor: colors.surface, borderWidth: 1, borderColor: colors.line, borderRadius: 10, padding: 14, marginRight: 12 },
 userMessage: { backgroundColor: colors.userBubble, borderColor: '#355171', marginLeft: 28, marginRight: 0 },
});
