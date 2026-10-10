import { Image, Text, View } from 'react-native';

export function ProviderLogo({ provider, size = 22, framed = false }: { provider: string; size?: number; framed?: boolean }) {
  const name = provider.trim().toLowerCase();
  const key = ['claude', 'claude code', 'anthropic'].includes(name) ? 'claude'
    : ['codex', 'openai', 'chatgpt'].includes(name) ? 'openai'
    : ['opencode', 'open code'].includes(name) ? 'opencode' : name === 'pi' ? 'pi' : 'agent';
  const source = key === 'claude' ? require('../../assets/providers/claude.png')
    : key === 'openai' ? require('../../assets/providers/openai.png')
    : key === 'opencode' ? require('../../assets/providers/opencode.png') : null;
  const color = key === 'claude' ? '#D97757' : '#F2F2F7';
  return <View accessibilityLabel={`${provider} logo`} accessible style={{width: framed ? size + 16 : size, height: framed ? size + 16 : size, alignItems: 'center', justifyContent: 'center', ...(framed ? {backgroundColor: '#262628', borderWidth: 1, borderColor: '#343437', borderRadius: 9} : {})}}>
    {source ? <Image source={source} resizeMode="contain" style={{width: size, height: size, tintColor: color}} />
      : <Text style={{color, fontSize: key === 'pi' ? size + 2 : size * .68, fontWeight: '600', lineHeight: size + 4, ...(key === 'pi' ? {fontFamily: 'Georgia'} : {fontFamily: 'monospace'})}}>{key === 'pi' ? 'π' : '>_'}</Text>}
  </View>;
}
