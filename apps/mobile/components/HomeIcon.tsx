import Svg, { Circle, G, Path, Rect } from 'react-native-svg';

export type HomeIconName = 'tasks' | 'reports' | 'employees' | 'branches' | 'inventory' | 'task-designer' | 'report-designer' | 'permissions' | 'settings' | 'home' | 'bell' | 'clock' | 'play' | 'check' | 'calendar' | 'chevron' | 'avatar';

export default function HomeIcon({ name, size = 32, color = '#0b3458', accent = '#dba62a' }: { name: HomeIconName; size?: number; color?: string; accent?: string }) {
  return <Svg width={size} height={size} viewBox="0 0 48 48" accessibilityElementsHidden importantForAccessibility="no-hide-descendants">
    <G fill="none" stroke={color} strokeWidth={3.2} strokeLinecap="round" strokeLinejoin="round">
      {name === 'tasks' && <><Rect x={11} y={9} width={27} height={34} rx={3} fill={color} /><Rect x={19} y={4} width={11} height={10} rx={2} fill="white" /><Path d="m18 29 5 5 10-12" stroke="white" /></>}
      {name === 'reports' && <><Rect x={5} y={32} width={6} height={11} fill={color} strokeWidth={0} /><Rect x={16} y={25} width={6} height={18} fill={color} strokeWidth={0} /><Rect x={27} y={18} width={6} height={25} fill={color} strokeWidth={0} /><Rect x={38} y={11} width={6} height={32} fill={color} strokeWidth={0} /><Path d="M5 25 19 14l8 4L42 4m-8 0h8v8" stroke={accent} /></>}
      {name === 'employees' && <><Circle cx={24} cy={12} r={7} fill={color} /><Circle cx={8} cy={14} r={5} fill={color} /><Circle cx={40} cy={14} r={5} fill={color} /><Path d="M12 41v-9a12 12 0 0 1 24 0v9Z" fill={color} /><Path d="M3 37v-9a6 6 0 0 1 7-6M45 37v-9a6 6 0 0 0-7-6" strokeWidth={6} /></>}
      {name === 'branches' && <><Path d="m5 15 19-12 19 12ZM7 42h34M9 20h30" fill={color} /><Path d="M12 22v17m24-17v17" strokeWidth={6} /><Rect x={21} y={27} width={6} height={13} fill={accent} strokeWidth={0} /><Circle cx={24} cy={12} r={2} fill="white" strokeWidth={0} /></>}
      {name === 'inventory' && <><Path d="M5 42V17L24 4l19 13v25M12 42V22h24v20" fill={color} /><Path d="M14 42V24h20v18" stroke="white" /><Path d="M16 29h6m4 0h6m-16 6h6m4 0h6m-16 6h6" stroke={accent} /></>}
      {name === 'task-designer' && <><Path d="M24 4C11 4 3 14 3 26c0 11 7 17 15 17 5 0 6-4 5-7-1-3 1-6 5-6h7c9 0 12-5 10-11C42 10 34 4 24 4Z" fill={color} /><Circle cx={14} cy={15} r={3} fill="white" strokeWidth={0} /><Circle cx={26} cy={11} r={3} fill="white" strokeWidth={0} /><Circle cx={9} cy={27} r={3} fill="white" strokeWidth={0} /><Path d="m23 39 19-20 4 4-19 20Z" fill={accent} stroke="white" strokeWidth={2} /></>}
      {name === 'report-designer' && <><Path d="M10 4h20l9 10v28H10Z" fill={color} /><Path d="M29 4v12h10M16 22h15m-15 7h12m-12 7h8" stroke="white" /><Circle cx={37} cy={37} r={10} fill={accent} stroke="white" strokeWidth={2} /><Path d="M37 32v10m-5-5h10" stroke="white" /></>}
      {name === 'permissions' && <><Path d="m24 3 18 7v15c0 10-11 17-18 21C17 42 6 35 6 25V10Z" fill={color} /><Rect x={16} y={21} width={16} height={14} rx={3} fill="white" strokeWidth={0} /><Path d="M19 21v-5a5 5 0 0 1 10 0v5" stroke="white" /><Path d="M24 27v3" stroke={color} /></>}
      {name === 'settings' && <><Path d="m20 4 8 0 2 6 5 3 6-1 4 7-4 5v6l4 5-4 7-6-1-5 3-2 6h-8l-2-6-5-3-6 1-4-7 4-5v-6l-4-5 4-7 6 1 5-3Z" fill={color} transform="translate(0 -3) scale(1 .94)" /><Circle cx={24} cy={23} r={8} fill="white" strokeWidth={0} /></>}
      {name === 'home' && <><Path d="m4 23 20-18 20 18M9 21v22h12V30h8v13h10V21" fill={color} /></>}
      {name === 'bell' && <><Path d="M11 32V20a13 13 0 0 1 26 0v12l4 5H7ZM19 42h10" fill={color} /><Path d="M24 4v3" /></>}
      {name === 'clock' && <><Circle cx={24} cy={24} r={20} fill={color} /><Path d="M24 11v14l10 7" stroke="white" /></>}
      {name === 'play' && <><Circle cx={24} cy={24} r={20} fill={color} /><Path d="m19 14 15 10-15 10Z" fill="white" strokeWidth={0} /></>}
      {name === 'check' && <><Circle cx={24} cy={24} r={20} fill={color} /><Path d="m13 24 8 8 15-17" stroke="white" strokeWidth={4} /></>}
      {name === 'calendar' && <><Rect x={7} y={9} width={34} height={34} rx={3} /><Path d="M7 18h34M16 4v10M32 4v10M15 26h2m7 0h2m7 0h2m-20 8h2m7 0h2m7 0h2" /></>}
      {name === 'chevron' && <Path d="m17 12 12 12-12 12" />}
      {name === 'avatar' && <><Circle cx={24} cy={15} r={9} fill={color} strokeWidth={0} /><Path d="M5 46v-5a19 19 0 0 1 38 0v5Z" fill={color} strokeWidth={0} /></>}
    </G>
  </Svg>;
}
