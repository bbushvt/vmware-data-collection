<template>
  <q-page>
    <q-dialog v-model='show_import_data_dialog'
      persistent translation-show='flip-down'
      translation-hide='flip-up'>
      <q-card>
        <q-card-section>
          <q-spinner color='primary' size='2em'/>
        </q-card-section>
      </q-card>
    </q-dialog>
    <div class='row justify-center'><h4>Enter vCenter Information</h4></div>
    <div class='row justify-center q-pb-md'><q-input bg-color="white" outlined
      v-model='vcenter_hostname' label='vCenter Hostname'/></div>
    <div class='row justify-center q-pb-md'><q-input bg-color="white" outlined
      v-model='vcenter_username' label='vCenter Username' /></div>
    <div class='row justify-center q-pb-md'><q-input bg-color="white" type='password'
            outlined v-model='vcenter_password' label='vCenter Password' /></div>
    <div class='row justify-center q-pb-md'>
      <q-checkbox v-model='anonymize' label='Anonymize Collection Data'
        @input='saveDisabled = true;'/>
    </div>
    <div class='row justify-center q-pb-md'>
      <div class="q-px-md">
        <q-btn color='primary' label='Collect Data' @click='probe_vcenter'/>
      </div>
      <div class="q-px-md">
        <q-btn :disable='saveDisabled' color='primary' label='Save Data' @click='save_data'/>
      </div>
    </div>
    <div class='row justify-center q-pb-md' v-if='data_collected'>{{message}}</div>
  </q-page>
</template>

<script>
const { ipcRenderer } = require('electron');

export default {
  name: 'PageIndex',
  data() {
    return {
      show_import_data_dialog: false,
      vcenter_hostname: '',
      vcenter_username: '',
      vcenter_password: '',
      output_file: '',
      data_collected: false,
      data_error: false,
      message: '',
      saveDisabled: true,
      vmdata: {},
      anonymize: false,
    };
  },
  methods: {
    import_data() {
      this.show_import_data_dialog = true;
    },
    probe_vcenter() {
      this.show_import_data_dialog = true;
      this.data_collected = false;
      this.message = '';
      this.data_error = false;

      ipcRenderer.send('get_vmware_data', {
        vcenter_hostname: this.vcenter_hostname,
        vcenter_username: this.vcenter_username,
        vcenter_password: this.vcenter_password,
        output_file: this.output_file,
        anonymize: this.anonymize,
      });
    },
    save_data() {
      ipcRenderer.send('save_file', this.vmdata);
    },
  },
  mounted() {
    this.$nextTick(() => {
      ipcRenderer.on('receive_vmare_data', (e, args) => {
        // eslint-disable-next-line
        //console.log(args);
        this.vmdata = args.data;
        this.data_collected = true;
        if (args.success === false) {
          this.data_error = true;
          this.message = 'Error: Please check parameters';
        } else {
          this.message = 'Successfully collected vCenter Data';
        }
        this.show_import_data_dialog = false;
        this.saveDisabled = false;
      });
    });
  },
};
</script>
