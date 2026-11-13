"""State, graph and budget regressions without network, credentials or generation."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).parents[1]
spec = importlib.util.spec_from_file_location('film_worker', ROOT / 'Resources/film_worker.py')
w = importlib.util.module_from_spec(spec)
spec.loader.exec_module(w)
score_spec=importlib.util.spec_from_file_location('film_score',ROOT/'Resources/film_score.py')
score=importlib.util.module_from_spec(score_spec);score_spec.loader.exec_module(score)
screen_spec=importlib.util.spec_from_file_location('film_screen',ROOT/'Resources/film_screen.py')
screen=importlib.util.module_from_spec(screen_spec);screen_spec.loader.exec_module(screen)


class FilmTests(unittest.TestCase):
    def test_locked_screenplay_hash_and_prior_outline_isolation(self):
        import hashlib
        script='RUNTIME_SECONDS: 90\nAlex waits for the alert.\nEND'
        spec=self.spec();spec['brief']='Approved film\nAPPROVED SHA256: '+hashlib.sha256(script.encode()).hexdigest()+'\n\n'+script
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]):
            f=w.Film(spec,tmp);f.state['project_outline']='Old unrelated awakening story'
            self.assertEqual(f.project_outline(),'')
            self.assertIn(script,f.approved_rules)
            spec['brief']+='Changed'
            with self.assertRaisesRegex(ValueError,'hash mismatch'):w.Film(spec,tmp)

    def test_reference_free_insert_never_invents_a_character_reference(self):
        shot=self.plan()['shots'][0];shot['reference_indices']=[]
        with self.assertRaisesRegex(ValueError,'artwork selection'):w.validate_shots({'shots':[shot]},shot['seconds'],1)
        shot.update(coverage_type='screen_insert',reference_free_reason='A hand-only insert contains no visible cast face or collectible identity')
        self.assertEqual(w.validate_shots({'shots':[shot]},shot['seconds'],1),[shot])
        shot['reference_indices']=[7]
        with self.assertRaisesRegex(ValueError,'artwork selection'):w.validate_shots({'shots':[shot]},shot['seconds'],1)
        shot['reference_indices']=[]
        for reason in (None, False, 123456789012, '', '   ', 'too short'):
            shot['reference_free_reason']=reason
            with self.subTest(reason=reason),self.assertRaisesRegex(ValueError,'artwork selection'):
                w.validate_shots({'shots':[shot]},shot['seconds'],1)
        shot['reference_free_reason']='Only a screen is visible, without an artwork-defined subject'
        shot['coverage_type']='character_closeup'
        with self.assertRaisesRegex(ValueError,'artwork selection'):
            w.validate_shots({'shots':[shot]},shot['seconds'],1)
        shot['coverage_type']='prop_insert'
        self.assertEqual(w.validate_shots({'shots':[shot]},shot['seconds'],1),[shot])

    def test_local_visual_only_blocks_cloud_still_fallback(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]):
            spec=self.spec();spec['local_render_only']=True;f=w.Film(spec,tmp)
            with patch.object(w,'http') as request:
                with self.assertRaisesRegex(ValueError,'cloud still rendering is disabled'):
                    f.grok_scene('prompt',[],b'',0)
                request.assert_not_called()

    def test_duration_subdivision_preserves_short_card_and_total(self):
        part=self.plan();base=part['shots'][0];card=dict(base,seconds=4);long=dict(base,seconds=6)
        part['shots']=[card,long];repaired={'shots':[card,dict(long,seconds=3),dict(long,seconds=3)]}
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]):
            f=w.Film(self.spec(),tmp)
            with patch.object(f,'claude',return_value=repaired) as editor:
                result=f.bound_shot_durations(part,10)
            self.assertEqual([s['seconds'] for s in result['shots']],[4,3,3]);editor.assert_called_once()
            self.assertEqual(part['shots'][1]['seconds'],6)
            with patch.object(f,'claude') as editor:
                self.assertEqual(f.bound_shot_durations(result,10),result);editor.assert_not_called()
            for invalid in ({'shots':[card,dict(long,seconds=5)]}, {'shots':[card,long]}):
                with patch.object(f,'claude',return_value=invalid),self.assertRaises(ValueError):
                    f.bound_shot_durations(part,10)

    def test_failed_shot_does_not_block_independent_clips(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]):
            f=w.Film(self.spec(),tmp);plan=self.plan();plan['shots']*=3;finished=[];calls={}
            def scene(plan,index):
                calls[index]=calls.get(index,0)+1
                if index==0 and calls[index]==1:raise ValueError('Scene 1 still fails review: wrong pose')
            with patch.object(f,'scene',side_effect=scene),patch.object(f,'render_clip',side_effect=lambda p,i:finished.append(i)),patch.object(f,'redirect_shot') as redirect:
                f.render_sequence(plan)
            self.assertEqual(finished,[1,2,0]);self.assertEqual(redirect.call_count,1)
            self.assertEqual(f.state['recovery_queue'],{})
            self.assertTrue(f.state['recovery_history'][0]['resolved'])

    def test_unresolved_shot_has_bounded_recovery_and_preserves_other_work(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]):
            f=w.Film(self.spec(),tmp);plan=self.plan();plan['shots']*=2;finished=[]
            def scene(plan,index):
                if index==0:raise ValueError('Reblocked scene 1 still fails review: wrong edition')
            with patch.object(f,'scene',side_effect=scene),patch.object(f,'render_clip',side_effect=lambda p,i:finished.append(i)),patch.object(f,'redirect_shot') as redirect:
                with self.assertRaisesRegex(ValueError,'Recovery needs attention for shots 1'):f.render_sequence(plan)
            self.assertEqual(finished,[1]);self.assertEqual(redirect.call_count,2)
            self.assertEqual(f.state['recovery_queue']['0']['attempts'],2)

    def test_recovery_does_not_hide_budget_failure(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]):
            f=w.Film(self.spec(),tmp)
            with patch.object(f,'scene',side_effect=ValueError('Film planning/review token limit reached')),patch.object(f,'redirect_shot') as redirect:
                with self.assertRaisesRegex(ValueError,'token limit'):f.render_sequence(self.plan())
                redirect.assert_not_called()

    def test_visual_pilot_failure_defers_without_claiming_completion(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]):
            f=w.Film(self.spec(),tmp)
            with patch.object(f,'pilot',side_effect=ValueError('Shot 1 still fails sampled-frame review')):
                f.optional_pilot(self.plan())
            self.assertIn('pilot_deferred',f.state);self.assertFalse(f.state.get('completed'))

    def test_completion_replaces_stale_progress_and_cached_resume_stays_offline(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(w.Film, 'preview_ref', return_value=[]):
            film = w.Film(self.spec(), tmp)
            film.state.update(status='Editing and encoding final', failure='old error')
            film.mark_completed()
            state = json.loads(film.state_file.read_text())
            self.assertTrue(state['completed'])
            self.assertEqual(state['status'], 'Completed — video ready')
            self.assertNotIn('failure', state)
            (film.root / 'final.mp4').write_bytes(b'test fixture')
            (film.root / 'shot-list.md').write_text('Finished report')
            film.state['status'] = 'Editing and encoding final'
            with patch.object(w, 'http', side_effect=AssertionError('Must not render again')), patch.object(w, 'emit') as emit:
                film.run()
                self.assertEqual(json.loads(film.state_file.read_text())['status'], 'Completed — video ready')
                self.assertEqual(emit.call_args.args[0], 'done')

    def test_instrumental_graph_has_matching_duration_and_local_model(self):
        g=score.score_graph('An original orchestral film motif.',204,76,'D minor',4090,'job/score')
        self.assertEqual(g['model']['inputs']['ckpt_name'],score.MODEL)
        self.assertEqual(g['text']['inputs']['duration'],g['latent']['inputs']['seconds'])
        self.assertEqual(g['text']['inputs']['lyrics'],'[Instrumental]')
        self.assertTrue(g['text']['inputs']['generate_audio_codes'])
        self.assertEqual(g['decode']['inputs']['vae'],['model',2])

    def test_display_quad_rejects_crossing_corners_tiny_planes_and_nan(self):
        good=[[.3,.1],[.7,.15],[.65,.9],[.25,.8]]
        self.assertEqual(screen.validate_quad(good),good)
        for bad in [[good[0],good[2],good[1],good[3]],[[.3,.3],[.31,.3],[.31,.31],[.3,.31]],[[float('nan'),0]]*4]:
            with self.assertRaises(ValueError):screen.validate_quad(bad)
        compile(screen.tracking_script(),'screen tracker','exec')

    def test_pending_audio_job_is_resumed_without_queuing_another_render(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]):
            f=w.Film(self.spec(),tmp);graph={'audio':'graph'};f.state['pending_job']={'id':'existing','signature':w.digest(graph)}
            output={'filename':'score.flac','subfolder':'job','type':'output'}
            with patch.object(w,'http',return_value={'existing':{'outputs':{'save':{'audio':[output]}},'status':{'status_str':'success'}}}) as api:
                self.assertEqual(f.comfy(graph,'music',0),(output,'existing'))
                self.assertEqual(api.call_count,1);self.assertIn('/history/existing',api.call_args.args[0])
                self.assertNotIn('pending_job',f.state)

    def spec(self):
        return {'server': 'http://127.0.0.1:8188', 'client_id': 'jarvis-test', 'seconds': 5,
                'brief':'A masked hero finds the right chase item','director_system':'Return only JSON.',
                'artwork': [{'source': 'hero.png', 'image': 'hero.png', 'sha256': 'a'}], 'max_grok_stills': 0}

    def plan(self):
        return {'continuity': 'One physical masked character, unchanged throughout.', 'shots': [{
            'seconds': 5, 'reference_indices': [0], 'reference_index': 0,
            'image_prompt': 'The hero in a physical collector room holding a phone.',
            'prompt': 'His thumb selects the lead while the camera tracks gently.',
            'purpose': 'The app provides the next lead.', 'narration': 'One lead remained.'}]}

    def test_duration_and_reference_contract(self):
        w.validate_shots(self.plan(), 5, 1, 1)
        bad = self.plan();bad['shots'][0]['seconds'] = 6
        with self.assertRaises(ValueError): w.validate_shots(bad, 5, 1)
        bad = self.plan();bad['shots'][0]['reference_indices'] = [2]
        with self.assertRaises(ValueError): w.validate_shots(bad, 5, 1)
        bad = self.plan();bad['shots'][0]['narration'] = 'word ' * 12
        with self.assertRaises(ValueError): w.validate_shots(bad, 5, 1)

    def test_character_free_coverage_requires_an_explicit_environment_flag(self):
        plan=self.plan();plan['shots'][0]['reference_indices']=[]
        with self.assertRaises(ValueError):w.validate_shots(plan,5,1)
        plan['shots'][0]['environment_only']=True;plan['shots'][0]['purpose']='The first retailer comes into view.'
        plan['shots'][0]['image_prompt']='A rainy retail forecourt with a single unbranded passing car.'
        plan['shots'][0]['prompt']='The car crosses the foreground while the storefront stays framed.'
        w.validate_shots(plan,5,1)

    def test_failed_critique_is_adjudicated_before_repainting(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]):
            f=w.Film(self.spec(),tmp)
            initial={'pass':False,'issues':'Only one eye visible in profile','regions':[]}
            accepted={'pass':True,'issues':'','regions':[]}
            with patch.object(f,'claude',side_effect=[initial,accepted]) as judge:
                result=f.review('CORE PURPOSE: show the hero comparing an item.',[],Path(tmp)/'review.json')
                self.assertTrue(result['pass']);self.assertEqual(result['initial_review'],initial)
                self.assertEqual(judge.call_count,2)
                self.assertIn('standard/chase distinction',judge.call_args.args[0])

    def test_whole_story_narration_keeps_silence_and_reuses_its_pass(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]):
            f=w.Film(self.spec(),tmp);plan=self.plan();plan['shots'].append(dict(plan['shots'][0],purpose='He leaves the shop.',narration=''))
            with patch.object(f,'claude',return_value={'cues':[{'shot':1,'narration':'The picture could only take him this far.'}]}) as writer:
                f.polish_narration(plan);plan['shots'][0]['image_prompt']='A simpler physical pose.'
                f.polish_narration(plan)
                self.assertEqual(writer.call_count,1)
                self.assertEqual(plan['shots'][1]['narration'],'')
                self.assertEqual(plan['shots'][0]['narration'],'The picture could only take him this far.')

    def test_narration_pass_cannot_move_a_line_to_another_shot(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]):
            f=w.Film(self.spec(),tmp);plan=self.plan();before=copy.deepcopy(plan)
            with patch.object(f,'claude',return_value={'cues':[{'shot':2,'narration':'An unsupported new cue.'}]}),self.assertRaises(ValueError):f.polish_narration(plan)
            self.assertEqual(plan,before)

    def test_reblocked_frame_survives_normal_scene_cache_checks(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]),patch.object(w,'image_block',return_value=[]):
            f=w.Film(self.spec(),tmp);plan=self.plan();data=b'reviewed pixels';(Path(tmp)/'scene-001.png').write_bytes(data)
            def adapt(plan,index,issues,frame=None):
                plan['shots'][index].update(purpose='Compare the exact edition.',image_prompt='A coherent close insert of the phone beside the figure.')
                return plan['shots'][index]
            with patch.object(f,'redirect_shot',side_effect=adapt),patch.object(f,'review',return_value={'pass':True,'issues':''}):
                record=f.reblock_scene(plan,0,data,{'filename':'good.png','type':'output'},'DARK','The proposed finger pose was impractical.')
            with patch.object(f,'comfy') as queue:
                self.assertEqual(f.scene(plan,0),record);queue.assert_not_called()
            self.assertTrue(record['blocking_reframed'])

    def test_camera_reframe_cannot_destroy_resolution_with_a_tiny_crop(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]):
            f=w.Film(self.spec(),tmp);plan=self.plan();plan['shots'][0]['reframe_crop']=[.5,.5,.51,.51]
            with patch.object(f,'redirect_shot',return_value=plan['shots'][0]),self.assertRaisesRegex(ValueError,'too much source detail'):
                f.reblock_scene(plan,0,b'pixels',{'filename':'frame.png'},'DARK','Peripheral anatomy')

    def test_director_can_remove_an_obsolete_camera_crop_on_resume(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]),patch.object(w,'image_block',return_value=[]):
            f=w.Film(self.spec(),tmp);plan=self.plan();plan['shots'][0]['reframe_crop']=[.1,.1,.9,.9]
            with patch.object(f,'claude',return_value={'usable':True,'reframe_crop':None}):f.redirect_shot(plan,0,'Use the complete picture.',frame=b'pixels')
            self.assertNotIn('reframe_crop',plan['shots'][0]);self.assertNotIn('reframe_crop',f.state['shot_overrides']['0']['after'])
            self.assertNotIn('reframe_crop',json.loads((Path(tmp)/'plan.json').read_text())['shots'][0])

    def test_visual_override_recovers_intermediate_version_without_replacing_new_voice(self):
        original=self.plan()['shots'][0];middle=dict(original,image_prompt='An intermediate camera setup.');latest=dict(middle,image_prompt='The final practical insert.')
        override={'before':original,'after':latest,'versions':[middle]}
        saved=dict(middle,narration='Newly timed narration.')
        self.assertTrue(w.apply_shot_override(saved,override));self.assertEqual(saved['image_prompt'],latest['image_prompt']);self.assertEqual(saved['narration'],'Newly timed narration.')
        edited=dict(original,image_prompt='An unrelated manual visual edit.')
        self.assertFalse(w.apply_shot_override(edited,override))

    def test_long_narration_keeps_candidate_for_shortening_without_rewriting_the_film(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]):
            f=w.Film(self.spec(),tmp);long={'cues':[{'shot':1,'narration':'word '*12}]}
            with patch.object(f,'claude',side_effect=[long,copy.deepcopy(long)]),self.assertRaises(ValueError):f.polish_narration(self.plan())
            resumed=w.Film(self.spec(),tmp)
            with patch.object(resumed,'claude',return_value={'cues':[{'shot':1,'narration':'He had mistaken hope for certainty.'}]}) as shorten:
                p=resumed.polish_narration(self.plan());self.assertEqual(shorten.call_count,1)
                self.assertEqual(p['shots'][0]['narration'],'He had mistaken hope for certainty.')

    def test_cancellation_clears_owned_pending_job_without_interrupting_other_work(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]):
            f=w.Film(self.spec(),tmp);f.active='own-job';f.state['active_prompt']='own-job';f.state['pending_job']={'id':'own-job','signature':'old'}
            with patch.object(w,'http',side_effect=[{}, {'queue_running':[[0,'someone-else']]}]) as call:
                f.cancel()
                self.assertEqual(call.call_count,2)
                self.assertEqual(call.call_args_list[0].args[1],{'delete':['own-job']})
                self.assertNotIn('pending_job',f.state);self.assertNotIn('active_prompt',f.state)
            w.STOP.clear()

    def test_planning_keeps_bible_and_shot_schemas_separate(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(w.Film,'preview_ref',return_value=[]):
            spec=self.spec();spec['brief']='Drop Assassin finds the right chase variant';spec['director_system']='Director instructions. Return only JSON: {"shots":[]}'
            film=w.Film(spec,tmp)
            bible={'title':'The Last Chase','concept':'The right edition matters.','continuity':self.plan()['continuity'],
                   'acts':[{'start':0,'end':5,'events':'He finds the correct chase item.','emotional_change':'Satisfaction'}]}
            with patch.object(film,'project_outline',return_value='A grounded hunt.'),patch.object(film,'ensure_cast'),patch.object(film,'claude',side_effect=[bible,bible,self.plan()]) as director:
                plan=film.plan()
                self.assertEqual(len(plan['shots']),1)
                self.assertIn('0 to 5 seconds',director.call_args_list[0].args[0])
                self.assertIn('STORY BIBLE phase',director.call_args_list[0].kwargs['system'])
                self.assertNotIn('"shots":[]',director.call_args_list[0].kwargs['system'])
                self.assertIn('Do NOT invent confidence scores',director.call_args_list[2].args[0])
                film.plan()
                self.assertEqual(director.call_count,3)

    def test_screenplay_requires_distinct_events_and_causal_states(self):
        goals=['Reveal a new physical detail %s'%i for i in range(6)]
        screenplay={'segments':[{'start':0,'end':30,'event':'Awaken and discover the tool','in_state':'A printed figure','out_state':'A living figure holding the phone','shot_goals':goals},
                                {'start':30,'end':60,'event':'Choose the exact target','in_state':'Phone awake, target unknown','out_state':'One exact chase saved','shot_goals':goals}]}
        w.validate_screenplay(screenplay,60)
        bad=copy.deepcopy(screenplay);bad['segments'][1]['event']=bad['segments'][0]['event']
        with self.assertRaisesRegex(ValueError,'repeats'):w.validate_screenplay(bad,60)
        bad=copy.deepcopy(screenplay);bad['segments'][1]['start']=29
        with self.assertRaisesRegex(ValueError,'timing'):w.validate_screenplay(bad,60)
        bad=copy.deepcopy(screenplay);bad['segments'][1]['shot_goals']=[]
        with self.assertRaisesRegex(ValueError,'shot goals'):w.validate_screenplay(bad,60)

    def test_new_screenplay_replaces_only_stale_cached_intervals(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]):
            spec=self.spec();spec['seconds']=60
            film=w.Film(spec,tmp)
            bible={'title':'The hunt','concept':'Find the right edition','continuity':self.plan()['continuity'],'acts':[{'start':0,'end':60,'events':'Awaken, choose and find','emotional_change':'Purpose'}]}
            (Path(tmp)/'film-bible.json').write_text(json.dumps(bible))
            schedule=[{'start':0,'end':30,'event':'Awaken'},{'start':30,'end':60,'event':'Choose the exact edition'}]
            part={'shots':[copy.deepcopy(self.plan()['shots'][0]) for _ in range(6)]}
            with patch.object(film,'project_outline',return_value=''),patch.object(film,'ensure_cast'),patch.object(film,'screenplay',return_value=schedule),patch.object(film,'pilot'),patch.object(film,'claude',side_effect=[copy.deepcopy(part),copy.deepcopy(part)]) as director:
                film.plan();self.assertEqual(director.call_count,2)
            (Path(tmp)/'plan.json').unlink()
            changed=copy.deepcopy(schedule);changed[0]['event']='Awaken for one specific hunt'
            with patch.object(film,'project_outline',return_value=''),patch.object(film,'ensure_cast'),patch.object(film,'screenplay',return_value=changed),patch.object(film,'pilot'),patch.object(film,'claude',return_value=copy.deepcopy(part)) as director:
                film.plan();self.assertEqual(director.call_count,1)
            self.assertEqual(json.loads((Path(tmp)/'plan-batch-00.json').read_text())['_schedule_signature'],w.digest(changed[0]))

    def test_overlong_narration_is_shortened_without_changing_picture_or_duration(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]):
            f=w.Film(self.spec(),tmp);part=self.plan();original=copy.deepcopy(part['shots'][0])
            part['shots'][0]['narration']='The real chase is knowing what to look for and who to share it with.'
            with patch.object(f,'claude',return_value={'narration':[{'index':0,'text':'Know your chase. Share the journey.'}]}):f.bound_narration(part)
            self.assertLessEqual(len(part['shots'][0]['narration'].split()),8)
            for key in ['seconds','reference_indices','image_prompt','prompt','purpose']:self.assertEqual(part['shots'][0][key],original[key])
            with patch.object(f,'claude') as director:f.bound_narration(part);director.assert_not_called()

    def test_story_arc_has_no_missing_or_overlapping_time(self):
        bible={'title':'The Last Chase','continuity':'One consistent masked hero with black and gold physical costume.',
               'acts':[{'start':0,'end':30,'events':['The hunt begins'],'emotional_change':'Curiosity'},
                       {'start':30,'end':60,'events':['The find resolves the hunt'],'emotional_change':'Satisfaction'}]}
        w.validate_bible(bible,60)
        for start in [29,31]:
            bad=copy.deepcopy(bible);bad['acts'][1]['start']=start
            with self.assertRaisesRegex(ValueError,'continuously'):w.validate_bible(bad,60)
        with self.assertRaisesRegex(ValueError,'length'):w.validate_bible(bible,600)

    def test_scene_graph_is_local_multi_reference(self):
        graph = w.scene_graph('New scene', ['hero.png', 'item.png'], 42, 'jarvis-test')
        self.assertEqual(graph['empty']['inputs']['width'], 1280)
        self.assertEqual(graph['schedule']['inputs']['steps'], 4)
        self.assertEqual(graph['guider']['inputs']['positive'], ['pos_1', 0])
        self.assertEqual(graph['pos_1']['inputs']['conditioning'], ['pos_0', 0])
        self.assertEqual(graph['neg_1']['inputs']['conditioning'], ['neg_0', 0])
        self.assertEqual(graph['model']['inputs']['unet_name'], 'flux-2-klein-4b.safetensors')
        self.assertNotIn('Flux2ProImageNode', json.dumps(graph))

    def test_end_guidance_is_applied_before_av_concat_and_removed_before_decode(self):
        template=json.loads((ROOT/'tests/video/ltx-workflow.json').read_text());original=copy.deepcopy(template)
        graph=w.video_graph(template,'One controlled forward step','start.png [output]',5,8,'job/shot',end_image='end.png [output]')
        self.assertEqual(template,original)
        self.assertEqual(graph['6']['class_type'],'EmptyLTXVLatentVideo')
        self.assertEqual(graph['start_guide']['inputs']['frame_idx'],0)
        self.assertEqual(graph['end_guide']['inputs']['frame_idx'],-1)
        self.assertEqual(graph['end_guide']['inputs']['latent'],['start_guide',2])
        self.assertEqual(graph['9']['inputs']['video_latent'],['end_guide',2])
        self.assertEqual(graph['13']['inputs']['positive'],['end_guide',0])
        self.assertEqual(graph['crop_guides']['inputs']['latent'],['15',0])
        self.assertEqual(graph['16']['inputs']['samples'],['crop_guides',2])
        self.assertEqual(graph['11']['inputs']['eta'],0)

    def test_ending_keyframe_uses_repaired_action_and_checks_visible_change(self):
        import hashlib
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]),patch.object(w,'image_block',return_value=[]):
            f=w.Film(self.spec(),tmp);plan=self.plan();(Path(tmp)/'scene-001.png').write_bytes(b'start')
            f.state['scenes']['0']={'sha256':hashlib.sha256(b'start').hexdigest(),'image':'start.png [output]'}
            target={'image_prompt':'The hand has turned, palm now facing the camera.','visible_change':'The palm is visible instead of the back of the hand.','reference_indices':[]}
            repaired='One wrist turn ends with the palm clearly visible.'
            with patch.object(f,'claude',return_value=target) as director,patch.object(f,'comfy',return_value=({'filename':'end.png','type':'output'},'id')),patch.object(f,'view',return_value=b'end'),patch.object(f,'review',return_value={'pass':True,'issues':''}) as judge:
                record=f.ending_scene(plan,0,motion=repaired)
                self.assertIn(repaired,director.call_args.args[0]);self.assertNotIn(plan['shots'][0]['prompt'],director.call_args.args[0])
                self.assertTrue(judge.call_args.kwargs['physical'])
                self.assertEqual(record['signature'],w.digest([f.state['scenes']['0']['sha256'],repaired,'local-ending-v2']))
            with patch.object(f,'comfy') as queue:
                self.assertEqual(f.ending_scene(plan,0,motion=repaired),record);queue.assert_not_called()

    def test_alternative_ending_requires_independent_physical_review(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]),patch.object(w,'image_block',return_value=[]):
            f=w.Film(self.spec(),tmp);plan=self.plan();f.state['scenes']['0']={'sha256':'start'}
            proposal={'usable':True,'prompt':'The hero turns his wrist once to present the phone toward the counter, then holds the new angle. Natural room ambience only.','visible_change':'The phone and wrist now face the counter.'}
            with patch.object(f,'claude',return_value=proposal),patch.object(f,'review',return_value={'pass':False,'issues':'No wrist change.'}) as judge:
                self.assertIsNone(f.reblock_ending(plan,0,'old motion',b'start',b'end',{'filename':'end.png'},'DARK','Wrong turn'))
                self.assertNotIn('0',f.state.get('end_scenes',{}));self.assertTrue(judge.call_args.kwargs['physical'])
            with patch.object(f,'claude',return_value=proposal),patch.object(f,'review',return_value={'pass':True,'issues':''}):
                result=f.reblock_ending(plan,0,'old motion',b'start',b'end',{'filename':'end.png'},'DARK','Wrong turn')
                self.assertEqual(result['motion_prompt'],proposal['prompt']);self.assertTrue(result['blocking_reframed'])

    def test_ending_director_can_simplify_a_cycle_and_cache_its_actual_motion(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]),patch.object(w,'image_block',return_value=[]):
            f=w.Film(self.spec(),tmp);plan=self.plan();(Path(tmp)/'scene-001.png').write_bytes(b'start')
            f.state['scenes']['0']={'sha256':'start','image':'start.png'}
            actual='The thumb moves once to the empty edge beside the loaded figure, then remains there while the other hand holds the phone steady.'
            target={'image_prompt':'The thumb now rests beside the figure.','visible_change':'Thumb moved from the bezel to the empty glass.','motion_prompt':actual,'reference_indices':[]}
            with patch.object(f,'claude',return_value=target),patch.object(f,'comfy',return_value=({'filename':'end.png'},'id')),patch.object(f,'view',return_value=b'end'),patch.object(f,'review',return_value={'pass':True,'issues':''}):
                record=f.ending_scene(plan,0,motion='Tap, slide, then lift away.')
            self.assertEqual(record['motion_prompt'],actual);self.assertEqual(record['signature'],w.digest(['start',actual,'local-ending-v2']))
            with patch.object(f,'comfy') as render:self.assertEqual(f.ending_scene(plan,0,motion=actual),record);render.assert_not_called()

    def test_first_take_uses_actual_image_direction_and_resume_reuses_it(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]),patch.object(w,'image_block',return_value=[]):
            spec=self.spec();spec['workflow']={};f=w.Film(spec,tmp);plan=self.plan()
            (Path(tmp)/'scene-001.png').write_bytes(b'start');f.state['scenes']['0']={'sha256':'start','image':'start.png'}
            direction='The two visible hands hold the loaded profile steady while the right wrist makes one small tilt.'
            with patch.object(f,'redirect_motion',return_value=direction) as director,patch.object(w,'video_graph',return_value={}) as graph,patch.object(f,'comfy',return_value=({'filename':'clip.mp4'},'id')) as render,patch.object(f,'view',return_value=b'video'),patch.object(f,'clip_frames',return_value=[]),patch.object(f,'review',return_value={'pass':True,'issues':''}):
                first=f.clip(plan,0);self.assertEqual(f.clip(plan,0),first)
                self.assertEqual(director.call_count,1);self.assertEqual(render.call_count,1)
                self.assertEqual(graph.call_args.args[1],direction);self.assertEqual(first['motion_prompt'],direction)

    def test_editorial_adaptation_cannot_bypass_independent_action_review(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]),patch.object(w,'image_block',return_value=[]):
            f=w.Film(self.spec(),tmp);plan=self.plan();before=copy.deepcopy(plan);(Path(tmp)/'scene-001.png').write_bytes(b'start')
            proposal={'usable':True,'purpose':'He studies the saved lead.','prompt':'The actor deliberately tilts the phone toward the light and settles at the new angle while reading the same profile.'}
            with patch.object(f,'claude',return_value=proposal),patch.object(f,'review',return_value={'pass':False,'issues':'Actor never moves.'}):
                self.assertIsNone(f.reblock_motion(plan,0,[],'Exact fingertip route differs.'))
            with patch.object(f,'claude',return_value=proposal),patch.object(f,'review',return_value={'pass':True,'issues':''}):
                actual=f.reblock_motion(plan,0,[],'Exact fingertip route differs.')
                self.assertEqual(actual['motion_prompt'],proposal['prompt']);self.assertEqual(plan,before)

    def test_unusable_motion_gets_one_restage_but_network_errors_do_not(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]):
            f=w.Film(self.spec(),tmp);plan=self.plan();bad=ValueError('Local ending frame still fails physical-change review: same pose')
            def restage(plan,index,reason):f.state['motion_restages']={'0':{'reason':reason}}
            with patch.object(f,'clip',side_effect=[bad,{'review':{'pass':True}}]) as render,patch.object(f,'restage_motion',side_effect=restage) as stage:
                self.assertTrue(f.render_clip(plan,0)['review']['pass']);self.assertEqual(render.call_count,2);self.assertEqual(stage.call_count,1)
            with patch.object(f,'clip',side_effect=bad),patch.object(f,'restage_motion') as stage:
                with self.assertRaises(ValueError):f.render_clip(plan,0)
                stage.assert_not_called()
            with patch.object(f,'clip',side_effect=RuntimeError('Network unavailable')),patch.object(f,'restage_motion') as stage:
                with self.assertRaises(RuntimeError):f.render_clip(plan,0)
                stage.assert_not_called()

    def test_guided_second_take_can_receive_independently_reviewed_screen_repair(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]),patch.object(w,'image_block',return_value=[]),patch.dict('sys.modules',{'film_screen':screen}):
            spec=self.spec();spec['workflow']={};f=w.Film(spec,tmp);plan=self.plan()
            (Path(tmp)/'scene-001.png').write_bytes(b'start');f.state['scenes']['0']={'sha256':'start','image':'start.png'}
            fixed={'filename':'fixed.mp4'};failed={'pass':False,'issues':'Phone display text changes.'};passed={'pass':True,'issues':''}
            with patch.object(f,'redirect_motion',return_value='One small phone tilt that settles.'),patch.object(w,'video_graph',return_value={}),patch.object(f,'comfy',return_value=({'filename':'raw.mp4'},'id')),patch.object(f,'view',return_value=b'video'),patch.object(f,'clip_frames',return_value=[]),patch.object(f,'review',side_effect=[failed,failed,passed]) as judge,patch.object(f,'reblock_motion',return_value=None),patch.object(f,'ending_scene',return_value={'image':'end.png','motion_prompt':'One small phone tilt that settles.'}),patch.object(screen,'stabilize_screen',side_effect=[None,(fixed,{'frames':121})]) as composite:
                result=f.clip(plan,0)
                self.assertEqual(composite.call_count,2);self.assertEqual(judge.call_count,3)
                self.assertEqual(result['output'],fixed);self.assertTrue(result['end_guided']);self.assertIn('screen_vfx',result)

    def test_larger_local_model_conditions_both_branches_on_all_references(self):
        graph=w.qwen_scene_graph('Repair the exact mask',['scene.png','hero.png','toy.png'],42,'job/qwen')
        self.assertEqual(graph['sample']['inputs']['steps'],40)
        self.assertEqual(graph['sample']['inputs']['cfg'],3.0)
        for branch in ['positive','negative']:
            self.assertEqual(graph[branch]['inputs']['image3'],['ref_2',0])
        self.assertEqual(graph['pos_method']['inputs']['reference_latents_method'],'index_timestep_zero')
        self.assertEqual(graph['norm']['inputs']['model'],['shift',0])
        fast=w.qwen_scene_graph('Repair',['hero.png'],42,'job/fast',lightning=True)
        self.assertEqual(fast['sample']['inputs']['steps'],4)
        self.assertEqual(fast['sample']['inputs']['cfg'],1.0)
        self.assertEqual(fast['shift']['inputs']['model'],['lightning',0])

    def test_larger_local_fallback_keeps_zero_cloud_budget(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]),patch.object(w,'image_block',return_value=[]):
            f=w.Film(self.spec(),tmp);f.has_qwen=True
            bad={'pass':False,'issues':'Wrong mask','regions':[]}
            good={'pass':True,'issues':''}
            with patch.object(f,'comfy',return_value=({'filename':'f.png','type':'output'},'id')),patch.object(f,'view',return_value=b'pixels'),patch.object(f,'review',side_effect=[bad,bad,bad,bad,good]),patch.object(f,'redirect_shot',side_effect=lambda plan,index,issues:plan['shots'][index]),patch.object(f,'qwen_frame',return_value=(b'fixed',{'filename':'q.png','type':'output'},'qwen-id',7)) as qwen,patch.object(f,'grok_scene') as cloud:
                record=f.scene(self.plan(),0)
                self.assertEqual(qwen.call_count,2)
                cloud.assert_not_called()
                self.assertEqual(f.state['grok_stills'],0)
                self.assertEqual(record['source'],'DARK Qwen-Image-Edit-2511')

    def test_three_reference_qwen_regeneration_does_not_drop_a_prop_or_make_a_board(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]):
            spec=self.spec();spec['artwork'] += [{'source':'June.png','image':'June.png','sha256':'b'},{'source':'chase.png','image':'chase.png','sha256':'c'}]
            f=w.Film(spec,tmp)
            with patch.object(f,'upload') as upload,patch.object(f,'comfy',return_value=({'filename':'new.png'},'id')) as queue,patch.object(f,'view',return_value=b'new'):
                f.qwen_frame(self.plan()['shots'][0],[0,1,2],b'bad-scene','Wrong figure',0)
                upload.assert_not_called()
                graph=queue.call_args.args[0]
                self.assertEqual([graph['ref_%s'%i]['inputs']['image'] for i in range(3)],['hero.png','June.png','chase.png'])

    def test_approved_protagonist_reference_is_retained_on_resume(self):
        import hashlib
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]):
            spec=self.spec();script='Alex is the visible protagonist. No other people appear.'
            spec.update(approved_screenplay=script,approved_screenplay_sha256=hashlib.sha256(script.encode()).hexdigest())
            spec['artwork'][0]['source']='company-logo.png'
            film=w.Film(spec,tmp);cast={'name':'Alex','description':'An original adult collector with short dark hair and a plain jacket.'}
            with patch.object(film,'claude',return_value={'cast':[cast]}) as director,patch.object(film,'comfy',return_value=({'filename':'alex.png','type':'output'},'id')),patch.object(film,'view',return_value=b'portrait-fixture'),patch.object(film,'review',return_value={'pass':True}),patch.object(w,'image_block',return_value=[]):
                film.ensure_cast({'title':'Approved story'})
            self.assertIn('INCLUDING the protagonist',director.call_args.args[0])
            ref=film.state['cast_references'][0]
            self.assertEqual(ref['cast_name'],'Alex')
            self.assertIn('only when this exact person is visible',ref['role'])
            self.assertNotIn('never substitute the main hero',ref['role'])
            self.assertEqual(len(spec['artwork']),1)
            resumed=w.Film(spec,tmp)
            with patch.object(resumed,'claude') as director,patch.object(resumed,'comfy') as renderer:
                resumed.ensure_cast({'title':'Approved story'})
                director.assert_not_called();renderer.assert_not_called()
            self.assertEqual(resumed.refs[-1]['cast_name'],'Alex')

    def test_generated_cast_does_not_mutate_job_artwork_or_checkpoint_hash(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]):
            spec=self.spec();film=w.Film(spec,tmp)
            film.state['cast_references']=[{'source':'Mara.png','image':'Mara.png [output]','sha256':'b','cast_name':'Mara'}];film.save()
            resumed=w.Film(spec,tmp)
            self.assertEqual(len(resumed.refs),2);self.assertEqual(len(spec['artwork']),1)
            self.assertEqual(resumed.state['spec_hash'],w.digest(spec))

    def test_local_inpaint_uses_the_existing_frame_latent(self):
        graph=w.inpaint_graph('Remove only the extra object','current.png','mask.png',['face.png'],7,'job/repair')
        self.assertEqual(graph['masked_latent']['inputs']['samples'],['enc_0',0])
        self.assertEqual(graph['sample']['inputs']['latent_image'],['masked_latent',0])
        self.assertEqual(graph['ref_0']['inputs']['image'],'current.png')
        self.assertEqual(graph['mask_channel']['inputs']['channel'],'red')
        self.assertEqual(w.repair_regions({'regions':None}),[])
        self.assertEqual(w.repair_regions({'regions':[{'box':[-.1,0,.5,.5],'edit':'bad'},{'box':[0,0,1,1],'edit':'global'}]}),[])
        self.assertEqual(len(w.repair_regions({'regions':[{'box':[.1,.2,.3,.4],'edit':'Empty this hand'}]})),1)

    def test_reviewed_candidate_is_adopted_without_regenerating(self):
        import hashlib
        with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]),patch.object(w,'image_block',return_value=[]):
            f=w.Film(self.spec(),tmp);plan=self.plan()
            with patch.object(f,'comfy',return_value=({'filename':'f.png','type':'output'},'id')),patch.object(f,'view',return_value=b'pixels'),patch.object(f,'review',return_value={'pass':True,'issues':''}):f.scene(plan,0)
            accepted=f.state['scenes'].pop('0');f.state['scene_candidates']['0']['review']={'pass':True,'issues':''}
            with patch.object(f,'comfy') as queue:
                record=f.scene(plan,0);queue.assert_not_called();self.assertEqual(record['sha256'],accepted['sha256'])

    def test_motion_animates_scene_not_poster(self):
        template = json.loads((ROOT/'tests/video/ltx-workflow.json').read_text())
        original = copy.deepcopy(template)
        graph = w.video_graph(template, 'Walk toward the item', 'scene-1.png [output]', 5, 8, 'job/shot')
        self.assertEqual(template, original)
        self.assertEqual(graph['6']['class_type'], 'LTXVImgToVideo')
        self.assertEqual(graph['jarvis_scene']['inputs']['image'], 'scene-1.png [output]')
        self.assertEqual(graph['9']['inputs']['video_latent'], ['6', 2])
        self.assertEqual(graph['13']['inputs']['positive'], ['6', 0])
        self.assertEqual(graph['8']['inputs']['frames_number'], 121)

    def test_scene_prompt_excludes_offscreen_cast(self):
        shot={'image_prompt':'A printed masked hero panel on wet glass. No people present.'}
        prompt=w.Film.scene_prompt(shot,['Image 1: approved identity only'])
        self.assertIn(shot['image_prompt'],prompt)
        self.assertIn('Do not add any person',prompt)
        self.assertNotIn('CONTINUITY:',prompt)

    def test_reviewed_scene_cache_and_corruption(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(w.Film, 'preview_ref', return_value=[]), patch.object(w, 'image_block', return_value=[]):
            film = w.Film(self.spec(), tmp)
            with patch.object(film, 'comfy', return_value=({'filename':'frame.png','subfolder':'job','type':'output'}, 'id')) as queue, patch.object(film, 'view', return_value=b'pixels'), patch.object(film, 'review', return_value={'pass':True,'issues':''}):
                first = film.scene(self.plan(), 0)
                second = film.scene(self.plan(), 0)
                self.assertEqual(first, second);self.assertEqual(queue.call_count, 1)
                (Path(tmp)/'scene-001.png').write_bytes(b'corrupted')
                film.scene(self.plan(), 0)
                self.assertEqual(queue.call_count, 2)

    def test_repeated_local_failures_trigger_direction_before_paid_still(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(w.Film,'preview_ref',return_value=[]),patch.object(w,'image_block',return_value=[]):
            film=w.Film(self.spec(),tmp);plan=self.plan()
            rewrite={'image_prompt':'A fully physical masked hero stands at the shop threshold.','prompt':'He takes one natural step toward the rain.','reference_indices':[0],'frame_identity':'One masked hero, unchanged.','narration':'One lead remained.'}
            with patch.object(film,'comfy',return_value=({'filename':'f.png','type':'output'},'id')) as local,patch.object(film,'view',return_value=b'pixels'),patch.object(film,'review',side_effect=[{'pass':False,'issues':'Impossible half-flat anatomy.'},{'pass':False,'issues':'Still impossible.'},{'pass':True,'issues':''}]),patch.object(film,'claude',return_value=rewrite),patch.object(film,'grok_scene') as paid:
                film.scene(plan,0)
                self.assertEqual(local.call_count,3);paid.assert_not_called()
                self.assertEqual(plan['shots'][0]['seconds'],5)
                self.assertEqual(plan['shots'][0]['purpose'],self.plan()['shots'][0]['purpose'])
                self.assertEqual(film.state['shot_overrides']['0']['before'],self.plan()['shots'][0])
            # A process restart replays the saved practical direction onto the original cached plan.
            (Path(tmp)/'plan.json').write_text(json.dumps(self.plan()))
            film.save();resumed=w.Film(self.spec(),tmp)
            self.assertEqual(resumed.plan()['shots'][0]['image_prompt'],rewrite['image_prompt'])

    def test_pending_comfy_job_is_not_submitted_twice(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(w.Film, 'preview_ref', return_value=[]):
            film = w.Film(self.spec(), tmp)
            graph = {'x': {'class_type':'SaveImage','inputs':{}}}
            film.state['pending_job'] = {'id':'same-job','signature':w.digest(graph)}
            response = {'same-job': {'outputs': {'x': {'images':[{'filename':'frame.png','type':'output'}]}}}}
            with patch.object(w, 'http', return_value=response) as network:
                output, ident = film.comfy(graph, 'scene', 0)
                self.assertEqual(ident, 'same-job')
                self.assertEqual(network.call_count, 1)
                self.assertIn('/history/same-job', network.call_args.args[0])
                self.assertNotIn('pending_job', film.state)

    def test_approved_identity_is_first_even_when_director_orders_props_first(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(w.Film, 'preview_ref', return_value=[]):
            spec=self.spec();spec['artwork'] += [{'source':'approved.png','image':'approved.png','sha256':'b','role':'approved cinematic look'}]
            f=w.Film(spec,tmp)
            self.assertEqual(f.scene_inputs({'reference_indices':[0,1]}),[1,0])
            self.assertEqual(f.scene_inputs({'reference_indices':[0]}),[0])
            self.assertEqual(f.scene_inputs({'reference_indices':[0],'image_prompt':'A hooded masked hero in the rain.'}),[0])

    def test_paid_still_cap_precedes_key_or_network(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(w.Film, 'preview_ref', return_value=[]):
            film = w.Film(self.spec(), tmp)
            with patch.object(w, 'read_key') as key, patch.object(w, 'http') as network:
                with self.assertRaisesRegex(ValueError, 'cap'): film.grok_scene('prompt', [0], b'x', 0)
                key.assert_not_called();network.assert_not_called()

    def test_checkpoint_rejects_different_story(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(w.Film, 'preview_ref', return_value=[]):
            f=w.Film(self.spec(), tmp);f.save()
            other=self.spec();other['seconds']=600
            with self.assertRaisesRegex(ValueError, 'different story'): w.Film(other, tmp)

    def test_redacts_keys_from_errors(self):
        with patch.dict(w.KEYS, {'grok':'xai-SecretKeyForUnitTestOnly'}):
            self.assertNotIn('xai-SecretKeyForUnitTestOnly', w.safe_error('bad key xai-SecretKeyForUnitTestOnly'))

    def test_director_budget_is_for_structured_output(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(w.Film, 'preview_ref', return_value=[]):
            spec = self.spec();spec['director_system'] = 'Return JSON';spec['model'] = 'claude-sonnet-5-5'
            f = w.Film(spec, tmp)
            reply = {'content':[{'type':'text','text':'{"pass":true}'}], 'usage':{'input_tokens':10,'output_tokens':8},'stop_reason':'end_turn'}
            with patch.object(w, 'read_key', return_value='unit-test-only'), patch.object(w, 'http', return_value=reply) as network:
                self.assertTrue(f.claude('review', maximum=700)['pass'])
                body = network.call_args.args[1]
                self.assertEqual(body['thinking'], {'type':'between_tools'})
                self.assertEqual(body['max_tokens'], 700)
            reply['stop_reason'] = 'max_tokens'
            with patch.object(w, 'read_key', return_value='unit-test-only'), patch.object(w, 'http', return_value=reply):
                with self.assertRaisesRegex(ValueError, 'truncated'):f.claude('review')

    def test_no_cloud_video_generation_endpoint(self):
        source=(ROOT/'Resources/film_worker.py').read_text()
        self.assertNotIn('/videos/generations', source)
        self.assertIn('grok-imagine-image-2.0', source)

unittest.main()
