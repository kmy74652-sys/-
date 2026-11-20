import * as Device from 'expo-device';
import * as Notifications from 'expo-notifications';
import Constants from 'expo-constants';
import { Platform } from 'react-native';
import { supabase } from './supabase';

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowAlert: true,
    shouldPlaySound: true,
    shouldSetBadge: true,
  }),
});

let registeredUserId: string | null = null;

export async function registerForPushNotifications(userId: string): Promise<string | null> {
  if (!supabase || !Device.isDevice || registeredUserId === userId) return null;

  if (Platform.OS === 'android') {
    await Notifications.setNotificationChannelAsync('default', {
      name: 'إشعارات برنامج الشاعري',
      importance: Notifications.AndroidImportance.MAX,
      vibrationPattern: [0, 250, 250, 250],
      lightColor: '#E5A93C',
      sound: 'default',
    });
  }

  const current = await Notifications.getPermissionsAsync();
  let finalStatus = current.status;
  if (finalStatus !== 'granted') {
    const requested = await Notifications.requestPermissionsAsync();
    finalStatus = requested.status;
  }
  if (finalStatus !== 'granted') return null;

  const projectId = Constants.expoConfig?.extra?.eas?.projectId ?? Constants.easConfig?.projectId;
  const tokenResponse = await Notifications.getExpoPushTokenAsync(projectId ? { projectId } : undefined);
  const token = tokenResponse.data;
  const { error } = await supabase.rpc('register_push_device', {
    p_expo_push_token: token,
    p_platform: Platform.OS,
    p_device_name: Device.deviceName ?? null,
  });
  if (error) throw error;
  registeredUserId = userId;
  return token;
}

export async function disablePushNotifications(): Promise<void> {
  if (!supabase) return;
  const { error } = await supabase.rpc('disable_push_device');
  if (error) throw error;
  registeredUserId = null;
}

export function resetPushRegistration(): void {
  registeredUserId = null;
}
