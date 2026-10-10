import '../components/theme.css';
import Head from 'expo-router/head';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { colors } from '../components/ui';
import { Provider } from '../lib/store';
export default function Layout() { return <Provider><Head><meta name="theme-color" content={colors.bg} /><meta name="color-scheme" content="dark" /></Head><StatusBar style="light" /><Stack screenOptions={{headerShown: false, contentStyle: {backgroundColor: colors.bg}}} /></Provider>; }
