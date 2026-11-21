import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { friendlyDataError } from '../lib/mobileData';
import { listMyDynamicReports, type DynamicEmployeeReport } from '../lib/dynamicReports';
import { reportDefaultDraft, validateReportFieldValue, evaluateReportField, type ReportField } from '../lib/reportSchema';
import { supabase } from '../lib/supabase';

type Submission = { id:string; form_id:string; report_date:string; answers:Record<string,unknown>; status:'draft'|'submitted'|'reviewed'|'approved'|'returned'; review_note:string|null; reviewed_by_name:string|null; approved_by_name:string|null };
const labels:Record<Submission['status'],string>={draft:'مسودة',submitted:'بانتظار مراجعة محمد',reviewed:'بانتظار اعتماد عبدالرحمن',approved:'معتمد نهائياً',returned:'أعيد للتعديل'};
function rawValue(field:ReportField,value:unknown):string {
 if(value===undefined||value===null)return reportDefaultDraft(field);
 return typeof value==='string'?value:JSON.stringify(value);
}
function parseAnswers(fields:ReportField, raw:string):unknown {
 if(raw.trim()==='')return undefined;
 if(['table','multiselect','signature','date_range','multi_image'].includes(fields.type))return JSON.parse(raw);
 if(['boolean','checkbox'].includes(fields.type))return raw==='true'?true:raw==='false'?false:raw;
 if(['number','integer','decimal','percentage','quantity','money','progress'].includes(fields.type)&&/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$/.test(raw.trim()))return Number(raw);
 return raw;
}
export default function ReportSubmissionEmployeePanel({branchId,canManageReports=false}:{branchId:string|null;canManageReports?:boolean}) {
 const [forms,setForms]=useState<DynamicEmployeeReport[]>([]);
 const [submissions,setSubmissions]=useState<Record<string,Submission>>({});
 const [values,setValues]=useState<Record<string,Record<string,string>>>({});
 const [loading,setLoading]=useState(true),[busy,setBusy]=useState(''),[error,setError]=useState(''),[notice,setNotice]=useState('');
 const load=useCallback(async()=>{
  if(!supabase){setError('قاعدة البيانات غير متاحة');setLoading(false);return;}
  if(!branchId){setError('لا يوجد فرع افتراضي مرتبط بحسابك. اطلب من الإدارة تحديد فرعك.');setLoading(false);return;}
  setLoading(true);setError('');
  try{
   const [available,auth]=await Promise.all([listMyDynamicReports(),supabase.auth.getUser()]);
   if(auth.error||!auth.data.user)throw auth.error??new Error('not_authenticated');
   const dates=[...new Set(available.map(x=>x.report_date))];
   let existing:Submission[]=[];
   if(available.length&&dates.length){
    const {data,error}=await supabase.from('report_submissions').select('id,form_id,report_date,answers,status,review_note,reviewed_by_name,approved_by_name').eq('employee_id',auth.data.user.id).eq('branch_id',branchId).in('form_id',available.map(x=>x.template_id)).in('report_date',dates);
    if(error)throw error;existing=(data??[]) as Submission[];
   }
   const byForm:Record<string,Submission>={};for(const row of existing)byForm[row.form_id]=row;
   setForms(available);setSubmissions(byForm);
   setValues(current=>{
    const next={...current};
    for(const form of available){
     const row=byForm[form.template_id];const draft={...(next[form.template_id]??{})};
     for(const field of form.fields){if(draft[field.key]===undefined)draft[field.key]=rawValue(field,row?.answers?.[field.key]);}
     next[form.template_id]=draft;
    }return next;
   });
  }catch(e){setError(friendlyDataError(e,'تعذر تحميل نماذج التقارير المستقلة.'));}
  finally{setLoading(false);}
 },[branchId]);
 useEffect(()=>{void load();},[load]);
 function buildAnswers(form:DynamicEmployeeReport,strict:boolean){
  const raw=values[form.template_id]??{},answers:Record<string,unknown>={};
  for(const field of form.fields){
   if(field.type==='calculated')continue;
   let value:unknown;
   try{value=parseAnswers(field,raw[field.key]??'');}catch{throw new Error('تنسيق غير صحيح في الحقل: '+field.label+' — أدخل قيمة JSON صحيحة.');}
   const issue=validateReportFieldValue(field,value);if(strict&&issue)throw new Error(issue);
   if(value!==undefined)answers[field.key]=value;
  }
  for(const field of form.fields)if(field.type==='calculated'){
   const result=evaluateReportField(field,form.fields,answers);if(result.value!==null)answers[field.key]=result.value;else if(strict)throw new Error('تعذر حساب الحقل: '+field.label);
  }
  return answers;
 }
 async function save(form:DynamicEmployeeReport,submit:boolean){
  if(!supabase||!branchId)return;
  const current=submissions[form.template_id];const editable=!current||current.status==='draft'||current.status==='returned';
  if(!editable)return;
  setBusy(form.template_id);setError('');setNotice('');
  try{
   const answers=buildAnswers(form,submit);
   if(!current){
    const auth=await supabase.auth.getUser();if(auth.error||!auth.data.user)throw auth.error??new Error('not_authenticated');
    const {data,error}=await supabase.from('report_submissions').insert({form_id:form.template_id,employee_id:auth.data.user.id,branch_id:branchId,report_date:form.report_date,answers,status:submit?'submitted':'draft'}).select('id').single();
    if(error)throw error;if(!data?.id)throw new Error('لم يتم إنشاء سجل التقرير.');
   }else{
    const {error}=await supabase.from('report_submissions').update({answers,...(submit?{status:'submitted'}:{})}).eq('id',current.id).select('id').single();
    if(error)throw error;
   }
   setNotice(submit?'تم رفع التقرير بنجاح، وأصبح بانتظار مراجعة محمد.':'تم حفظ مسودة التقرير بأمان.');
   await load();
  }catch(e){setError(friendlyDataError(e,'تعذر حفظ التقرير أو رفعه.'));}
  finally{setBusy('');}
 }
 if(loading)return <View style={s.center}><ActivityIndicator color="#17324d"/><Text style={s.muted}>جارٍ تحميل نماذج التقارير…</Text></View>;
 if(!forms.length)return <View style={s.empty}><Text style={s.title}>لا توجد نماذج تقارير معتمدة لدورك</Text><Text style={s.muted}>ستظهر النماذج التي اعتمدتها الإدارة وحددتها لتصنيفك الوظيفي هنا.</Text>{canManageReports&&<Text style={s.muted}>يمكنك فتح مصمم التقارير من لوحة الإدارة لإدارة النماذج.</Text>}</View>;
 return <View style={s.wrap}>
  <View style={s.intro}><Text style={s.title}>تقارير الموظف المستقلة</Text><Text style={s.muted}>هذه التقارير منفصلة عن تقارير المهام. احفظ المسودة أولاً أو ارفع التقرير لإرساله إلى محمد للمراجعة.</Text></View>
  {forms.map(form=>{
   const row=submissions[form.template_id];const status=row?.status??'draft';const locked=!!row&&['submitted','reviewed','approved'].includes(row.status);
   return <View key={form.template_id} style={s.card}>
    <View style={s.header}><Text style={s.formTitle}>{form.title}</Text><Text style={[s.badge,status==='returned'?s.returned:undefined]}>{labels[status]}</Text></View>
    {!!form.description&&<Text style={s.muted}>{form.description}</Text>}
    <Text style={s.meta}>تاريخ التقرير: {form.report_date} · الفرع: {branchId}</Text>
    {!!row?.review_note&&<Text style={s.note}>ملاحظة الإدارة: {row.review_note}</Text>}
    {form.fields.map(field=><View key={field.key} style={s.field}>
     <Text style={s.label}>{field.label}{field.required?' *':''}</Text>
     {!!field.description&&<Text style={s.muted}>{field.description}</Text>}
     <TextInput editable={!locked} value={values[form.template_id]?.[field.key]??''} onChangeText={v=>setValues(p=>({...p,[form.template_id]:{...p[form.template_id],[field.key]:v}}))} placeholder={field.type==='table'||field.type==='multiselect'||field.type==='date_range'||field.type==='signature'?'أدخل القيمة بصيغة JSON':field.type==='datetime'?'يُسجل الوقت عند إدخال الإجابة':'اكتب إجابتك هنا'} multiline={['long_text','decision_notes','textarea','table','multiselect','date_range','signature'].includes(field.type)} textAlign="right" style={[s.input,['long_text','decision_notes','textarea','table','multiselect','date_range','signature'].includes(field.type)&&s.multiline]}/>
    </View>)}
    {!locked&&<View style={s.actions}><Pressable disabled={busy===form.template_id} style={s.secondary} onPress={()=>void save(form,false)}><Text style={s.secondaryText}>{busy===form.template_id?'جارٍ الحفظ…':'حفظ مسودة'}</Text></Pressable><Pressable disabled={busy===form.template_id} style={s.primary} onPress={()=>void save(form,true)}><Text style={s.primaryText}>{busy===form.template_id?'جارٍ الرفع…':status==='returned'?'إعادة الرفع للمراجعة':'رفع التقرير لمحمد'}</Text></Pressable></View>}
    {locked&&<Text style={s.locked}>تم قفل الإجابات بعد الرفع حتى لا تتغير أثناء المراجعة والاعتماد.</Text>}
    {!!row?.reviewed_by_name&&<Text style={s.meta}>المراجع: {row.reviewed_by_name}</Text>}
    {!!row?.approved_by_name&&<Text style={s.meta}>المعتمد: {row.approved_by_name}</Text>}
   </View>;
  })}
  {!!notice&&<Text style={s.notice}>{notice}</Text>}{!!error&&<Text accessibilityRole="alert" style={s.error}>{error}</Text>}
  <Pressable style={s.refresh} onPress={()=>void load()}><Text style={s.secondaryText}>تحديث النماذج والتقارير</Text></Pressable>
 </View>;
}
const s=StyleSheet.create({wrap:{gap:12},center:{padding:20,alignItems:'center',gap:8},intro:{backgroundColor:'#edf3f8',borderRadius:13,padding:13,gap:6},title:{color:'#17324d',fontSize:16,fontWeight:'900',textAlign:'right'},muted:{color:'#687d8e',fontSize:12,lineHeight:20,textAlign:'right'},empty:{backgroundColor:'#fff',padding:15,borderRadius:13,gap:8},card:{backgroundColor:'#fff',borderRadius:14,borderWidth:1,borderColor:'#dce5eb',padding:13,gap:10},header:{flexDirection:'row-reverse',alignItems:'center',justifyContent:'space-between',gap:8},formTitle:{flex:1,color:'#17324d',fontSize:16,fontWeight:'900',textAlign:'right'},badge:{backgroundColor:'#fff2d7',color:'#72551b',padding:7,borderRadius:12,fontSize:10,fontWeight:'800'},returned:{backgroundColor:'#fff0dc',color:'#9b542e'},meta:{color:'#718394',fontSize:11,textAlign:'right'},note:{color:'#8a5b16',backgroundColor:'#fff4d7',padding:9,borderRadius:9,textAlign:'right'},field:{gap:5},label:{color:'#29475a',fontWeight:'800',textAlign:'right'},input:{minHeight:45,borderWidth:1,borderColor:'#d6e0e4',borderRadius:9,padding:10,color:'#17324d',backgroundColor:'#fbfcfc'},multiline:{minHeight:85,textAlignVertical:'top'},actions:{flexDirection:'row-reverse',gap:8},primary:{flex:1,minHeight:45,backgroundColor:'#17324d',borderRadius:9,alignItems:'center',justifyContent:'center',padding:9},primaryText:{color:'#fff',fontWeight:'900'},secondary:{minHeight:45,flex:1,backgroundColor:'#e8f0f3',borderRadius:9,alignItems:'center',justifyContent:'center',padding:9},secondaryText:{color:'#17324d',fontWeight:'900'},locked:{color:'#687d8e',fontSize:11,textAlign:'right'},notice:{color:'#23633c',backgroundColor:'#e8f5eb',padding:10,borderRadius:9,textAlign:'right'},error:{color:'#a8443d',backgroundColor:'#fff0ef',padding:10,borderRadius:9,textAlign:'right'},refresh:{padding:11,backgroundColor:'#e8f0f3',borderRadius:9,alignItems:'center'}});
