import { Platform } from 'react-native';
import * as SecureStore from 'expo-secure-store';
import AsyncStorage from '@react-native-async-storage/async-storage';
const key = 'open-one.desktop-connection';
export const credentials = {
  get: async () => {
    if (Platform.OS !== 'web') return SecureStore.getItemAsync(key);
    if (/^#[A-Za-z0-9_-]{32,256}$/.test(window.location.hash)) {
      const link = window.location.href;
      window.history.replaceState(null, '', window.location.pathname);
      return link;
    }
    return sessionStorage.getItem(key);
  },
  set: (value: string) => Platform.OS === 'web' ? Promise.resolve(sessionStorage.setItem(key, value)) : SecureStore.setItemAsync(key, value),
  remove: () => Platform.OS === 'web' ? Promise.resolve(sessionStorage.removeItem(key)) : SecureStore.deleteItemAsync(key),
};
export const drafts = AsyncStorage;
